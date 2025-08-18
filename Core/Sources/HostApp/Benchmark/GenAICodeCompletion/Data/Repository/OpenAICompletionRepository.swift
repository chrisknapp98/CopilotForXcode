import Foundation

struct OpenAICompletionRepository: CodeCompletionRepository {

    enum OpenAIError: Error {
        case badResponse(status: Int, body: String)
        case decoding
        case emptyChoice
    }

    struct Config {
        var apiKey: String
        /// e.g. "gpt-4o-mini"
        var model: String
        /// Optional org header
        var organization: String?
        /// API base, keep default unless using a proxy
        var baseURL: URL

        init(
            apiKey: String,
            model: String,
            organization: String? = nil,
            baseURL: URL = URL(string: "https://api.openai.com/v1")!
        ) {
            self.apiKey = apiKey
            self.model = model
            self.organization = organization
            self.baseURL = baseURL
        }
    }

    struct JSONOnly: Encodable { let type: String = "json_object" }

    private let config: Config
    private let urlSession: URLSession

    init(config: Config, session: URLSession = .shared) {
        self.config = config
        self.urlSession = session
    }

    func structuredEdit(for request: SuggestionRequest) async throws -> CodeEdit {
        var urlRequest = URLRequest(url: config.baseURL.appendingPathComponent("chat/completions"))
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        if let org = config.organization { urlRequest.setValue(org, forHTTPHeaderField: "OpenAI-Organization") }
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let payload = ChatPayload(
            model: config.model,
            messages: buildMessagesForStructuredEdit(from: request),
            temperature: 0,
            stream: false,
            response_format: JSONOnly()  // ask for a single JSON object
        )
        urlRequest.httpBody = try JSONEncoder().encode(payload)

        let (data, resp) = try await urlSession.data(for: urlRequest)
        guard let http = resp as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
            let body = String(data: data, encoding: .utf8) ?? "<non-utf8>"
            throw OpenAIError.badResponse(status: (resp as? HTTPURLResponse)?.statusCode ?? -1, body: body)
        }

        let decoded = try JSONDecoder().decode(ChatResponse.self, from: data)
        guard let content = decoded.choices.first?.message.content, !content.isEmpty else {
            throw OpenAIError.emptyChoice
        }

        // The model's entire reply is a JSON object. Decode it.
        let edit = try JSONDecoder().decode(CodeEdit.self, from: Data(content.utf8))
        let fixedSuggestionText = removeClosingBraceIfNeeded(
            suggestion: edit.text,
            promptCode: request.content,
            line: request.cursorPosition.line
        )
        let fixedEdit = CodeEdit(text: fixedSuggestionText, range: edit.range)
        return fixedEdit
    }
    
    private func removeClosingBraceIfNeeded(suggestion: String, promptCode: String, line: Int) -> String {
        // Defensive: find the first line AFTER the cursor line
        let promptLines = promptCode.components(separatedBy: "\n")
        guard line + 1 < promptLines.count else { return suggestion }
        let afterFirstLineTrimmed = promptLines[line + 1].trimmingCharacters(in: .whitespacesAndNewlines)

        // Work on line array of the suggestion
        var lines = suggestion.components(separatedBy: "\n")

        // Find the last *non-empty* line (ignoring pure whitespace)
        var lastNonEmptyIndex: Int?
        for i in lines.indices.reversed() {
            if !lines[i].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                lastNonEmptyIndex = i
                break
            }
        }
        guard let idx = lastNonEmptyIndex else { return suggestion } // all whitespace? leave as-is

        let tailTrimmed = lines[idx].trimmingCharacters(in: .whitespacesAndNewlines)

        // If the model echoed the first AFTER line (e.g. a closing brace), drop it
        if !afterFirstLineTrimmed.isEmpty, tailTrimmed == afterFirstLineTrimmed {
            // Remove that line and any trailing blank lines after it
            lines.removeSubrange(idx..<lines.count)
            // If you want to keep exactly one trailing newline, you can add:
            // if !lines.isEmpty, !lines.last!.isEmpty { lines.append("") }
            return lines.joined(separator: "\n")
        }

        return suggestion
    }
    
    private func detectLanguage(from path: String) -> String {
        switch (path as NSString).pathExtension.lowercased() {
        case "swift": return "Swift"
        default: return "Unknown"
        }
    }

    private func buildMessagesForStructuredEdit(from req: SuggestionRequest) -> [ChatMessage] {
        let language = detectLanguage(from: req.relativePath)

        let before = String(req.content.prefix(req.cursorOffset))
        let after  = String(req.content.suffix(max(0, req.content.count - req.cursorOffset)))

        // Defensive: if the line index is in range, grab the full original line text
        let lineIndex = max(0, min(req.cursorPosition.line, max(0, req.lines.count - 1)))
        let currentLine = lineIndex < req.lines.count ? req.lines[lineIndex] : ""

        let indentDescriptor: String = req.usesTabsForIndentation
            ? "tabs=\(req.tabSize)"
            : "spaces=\(req.indentSize)"

        let related = req.relevantCodeSnippets.map { s in
            """
            PATH: \(s.path)
            LANG: \(s.language ?? "unknown")
            ----
            \(s.code)
            """
        }.joined(separator: "\n\n========\n\n")

        let system = ChatMessage(role: "system", content: """
        You are a \(language) inline code completion engine.

        Complete the body of only the current function. Produce meaningful, compilable code using identifiers in scope. No placeholders (e.g., "TODO", "// Implementation goes here").
        Return ONE compact JSON object and nothing else (no code fences, no prose).

        Semantics:
        - Range describes from what line and character to what line and character the output text should be replaced
        - Ranges use 0-based LSP-style coordinates: (start, end).
        - Coordinates are relative to the current (pre-edit) buffer.
        - The replacement range MUST cover the entire CURRENT LINE (from character 0).
        - You can extend the range into following lines to complete the construct.
        - The output text will be inserted in the given range.

        Output requirements:
        - The "text" must include the full updated CURRENT LINE (where the cursor is) including the function definition and any additional lines needed to complete the implementation.
        - IMPORTANT: As can be seen in AFTER, the closing brace `}` of the function to complete is already existing. It MUST not be included in output text. Otherwise a duplicated brace will lead to a compilation error.
        - Do NOT begin the text with the first bytes of AFTER.
        - No placeholders or comments like "TODO" or "// Implementation goes here".
        - Respect indentation \(indentDescriptor) and file style.
        - Tabs are represented as spaces in the input; preserve that.
        - Preserve newlines; avoid trailing whitespace.

        Respond only with JSON of shape:
        {
          "text": "STRING",
          "range": {
            "start": { "line": INT, "character": INT },
            "end":   { "line": INT, "character": INT }
          }
        }
        """)
        
        // Few-shot example teaches the model that we want a body, not just "}"
        let exampleUser = ChatMessage(role: "user", content:
    """
    EXAMPLE ONLY — DO NOT SOLVE THIS:
    FILE: Example.swift
    LANGUAGE_HINT: Swift
    CURRENT_LINE_INDEX: 1
    CURRENT_LINE_TEXT:
    «««
        func greet() {\n
    »»»
    CURSOR_CHARACTER: 18
    BEFORE:
    «««
    struct Greeter {\n    func greet() {
    »»»
    <CURSOR>
    AFTER:
    «««
    \n    }\n}
    »»»
    Respond with JSON:
    {
      "text": "func greet() {\n        print(\"Hello\")\n",
      "range": { "start": { "line": 1, "character": 0 }, "end": { "line": 1, "character": 18 } }
    }
    """
        )

        // Instruct exact JSON shape
        let user = ChatMessage(role: "user", content:
    """
    FILE: \(req.relativePath)
    LANGUAGE_HINT: \(language)

    CURRENT_LINE_INDEX: \(lineIndex)
    CURRENT_LINE_TEXT:
    «««
    \(currentLine)
    »»»
    CURSOR_CHARACTER: \(req.cursorPosition.character)

    BEFORE:
    «««
    \(before)
    »»»

    <CURSOR>

    AFTER:
    «««
    \(after)
    »»»

    OPTIONAL RELEVANT CONTEXT:
    «««
    \(related)
    »»»

    Respond with **only** a compact JSON object of this shape (no code fences, no trailing text):
    {
      "text": "STRING — the replacement text (must include the full updated CURRENT LINE as it should appear after the edit; may include multiple lines if needed)",
      "range": {
        "start": { "line": INT, "character": INT },
        "end":   { "line": INT, "character": INT }
      }
    }
    Rules:
    - Choose a minimal range that replaces from the start you need to change up to the end you need to change.
    - The range MUST at least span the entire CURRENT LINE (i.e., covers from (CURRENT_LINE_INDEX, 0) to some end on the same or later line), so that the returned `text` fully defines that line after the edit.
    - Do not include explanations or formatting fences.
    """
        )

        return [system, exampleUser, user]
    }
}
