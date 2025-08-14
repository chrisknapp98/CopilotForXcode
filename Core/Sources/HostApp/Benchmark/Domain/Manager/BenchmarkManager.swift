import Foundation
import AppKit
import Dependencies
import Workspace
import Service
import XcodeInspector
import PromptToCodeService
import SuggestionBasic
import SuggestionProvider
import SuggestionService
import WorkspaceSuggestionService
import CopilotForXcodeKit

import BuiltinExtension
import GitHubCopilotService

import Combine


protocol BenchmarkManager {
    
}

class RealtimeSuggestionControllerBenchmarkManager: BenchmarkManager {
    private let benchmarkSettingsRepository: BenchmarkSettingsRepository
    @WorkspaceActor
    private let workspacePool: WorkspacePool
    
    private let isMultiFileEnabledSubject = CurrentValueSubject<Bool, Never>(true)
    var isMultiFileEnabled: AnyPublisher<Bool, Never> {
        isMultiFileEnabledSubject.eraseToAnyPublisher()
    }
    private let taskStatesSubject = CurrentValueSubject<[TaskStatus], Never>([])
    var taskStates: AnyPublisher<[TaskStatus], Never> {
        taskStatesSubject.eraseToAnyPublisher()
    }
    
    init(benchmarkSettingsRepository: BenchmarkSettingsRepository) {
        @Dependency(\.workspacePool) var workspacePool
        BuiltinExtensionManager.shared.setupExtensions([
            GitHubCopilotExtension(workspacePool: workspacePool)
        ])
        workspacePool.registerPlugin {
            SuggestionServiceWorkspacePlugin(workspace: $0) { SuggestionService.service() }
        }
        workspacePool.registerPlugin {
            GitHubCopilotWorkspacePlugin(workspace: $0)
        }
        workspacePool.registerPlugin {
            BuiltinExtensionWorkspacePlugin(workspace: $0)
        }
        self.workspacePool = workspacePool
        self.benchmarkSettingsRepository = benchmarkSettingsRepository
    }
    
    func getCodeSuggestions(at benchmarkDirectory: BenchmarkDirectory) async throws {
        let taskPaths: [URL] = getTaskFolders(in: benchmarkDirectory.url)
        let initialTaskStates = taskPaths.map { _ in TaskStatus.notStarted }
        await updateTaskStates(initialTaskStates)
        for (index, taskPath) in taskPaths.prefix(1).enumerated() {
            await updateTaskStatus(.running, at: index)
            if let suggestion = await getCodeSuggestionFromService(at: taskPath, from: benchmarkDirectory.url) {
//            if let suggestion = await getCodeSuggestionFromOpenAI(at: taskPath, from: benchmarkDirectory.url) {
                await applyCodeSuggestion(suggestion: suggestion.suggestion, at: suggestion.fileURL)
                await storeContentInOutputDirectory(suggestion, for: index+1, in: benchmarkDirectory)
                await updateTaskStatus(.success, at: index)
                try await Task.sleep(nanoseconds: 3_000_000_000)
            } else {
                await updateTaskStatus(.failure, at: index)
            }
            await cleanUp()
        }
    }
    
    func getCodeSuggestionFromService(at directory: URL, from benchmarkDirectory: URL) async -> SuggestionResponse? {
        guard let metadata: MetadataDTO = readMetadata(at: directory),
              let xcodeWorkspaceFileURL = findXcodeWorkspace(in: benchmarkDirectory),
              let workspace = try? await workspacePool.fetchOrCreateWorkspace(workspaceURL: xcodeWorkspaceFileURL)
        else { return nil }
        let entrypoint = metadata.mapToEntrypoint(prefixing: benchmarkDirectory.path)
        let content: String = (try? String(contentsOf: entrypoint.fileURL, encoding: .utf8)) ?? ""
        
        let multiFileContextManager = MultiFileContextManager(
            workspaceProvider: ManualWorkspaceProvider(workspace: workspace),
            parser: SwiftProgrammingLanguageSyntaxParser()
        )
        let relevantSymbols: [SymbolContent] = await {
            if isMultiFileEnabledSubject.value {
                let symbols = await multiFileContextManager.retrieveRelevantSymbolsForFileContent(content: content)
                return Array(symbols.values)
            } else {
                return []
            }
        }()
        
        let suggestionRequest = SuggestionProvider.SuggestionRequest(
            fileURL: entrypoint.fileURL,
            relativePath: entrypoint.fileURL.path.replacingOccurrences(of: benchmarkDirectory.path, with: ""),
            content: content,
            originalContent: content,
            lines: content.linesWithNewlineSuffix,
            cursorPosition: entrypoint.cursor,
            cursorOffset: content.cursorOffset(line: entrypoint.cursor.line, character: entrypoint.cursor.character) ?? 0,
            tabSize: 4,
            indentSize: 4,
            usesTabsForIndentation: false,
            relevantCodeSnippets: relevantSymbols.mapToRelevantCodeSnippets()
        )
        let workspaceInfo = WorkspaceInfo(workspaceURL: xcodeWorkspaceFileURL, projectURL: benchmarkDirectory)
        await openFilespaces(entrypoint: entrypoint, relevantSymbols: relevantSymbols, in: workspace)
        await simulateInitialEditorChange(entrypoint: entrypoint, content: content, in: workspace)
        do {
            // only works when setting document version GitHubCopilotService to 0
            let suggestions = try await workspace.suggestionService?.getSuggestions(suggestionRequest, workspaceInfo: workspaceInfo)
            await saveFilespace(entrypoint: entrypoint, in: workspace)
            await closeFilespaces(entrypoint: entrypoint, relevantSymbols: relevantSymbols, in: workspace)
//            let suggestions: [SuggestionBasic.CodeSuggestion]? = [exampleSuggestion]
            guard let suggestions, let firstSuggestion = suggestions.first else { return nil }
            return .init(
                suggestion: firstSuggestion,
                fileURL: entrypoint.fileURL,
                relevantSymbolsFromRequest: relevantSymbols
            )
        } catch {
            print("CK \(error)")
            return nil
        }
//        return nil
    }
    
    private func openFilespaces(entrypoint: EntryPoint, relevantSymbols: [SymbolContent], in workspace: Workspace) async {
        for symbol in relevantSymbols {
            if let filespace = try? await workspace.createFilespaceIfNeeded(fileURL: URL(fileURLWithPath: symbol.fileURL)) {
                await workspace.didOpenFilespace(filespace)
            }
        }
        if let filespace = try? await workspace.createFilespaceIfNeeded(fileURL: entrypoint.fileURL) {
            await workspace.didOpenFilespace(filespace)
        }
    }
    
    private func closeFilespaces(entrypoint: EntryPoint, relevantSymbols: [SymbolContent], in workspace: Workspace) async {
        for symbol in relevantSymbols {
            await workspace.didCloseFilespace(URL(fileURLWithPath: symbol.fileURL))
        }
        await workspace.didCloseFilespace(entrypoint.fileURL)
    }
    
    private func saveFilespace(entrypoint: EntryPoint, in workspace: Workspace) async {
        if let filespace = try? await workspace.createFilespaceIfNeeded(fileURL: entrypoint.fileURL) {
            await workspace.didSaveFilespace(filespace)
        }
    }
    
    private func simulateInitialEditorChange(entrypoint: EntryPoint, content: String, in workspace: Workspace) async {
        await workspace.didUpdateFilespace(fileURL: entrypoint.fileURL, content: content, version: 1)
    }
    
    func getCodeSuggestionFromOpenAI(at directory: URL, from benchmarkDirectory: URL) async -> SuggestionResponse? {
        guard let metadata: MetadataDTO = readMetadata(at: directory),
              let xcodeWorkspaceFileURL = findXcodeWorkspace(in: benchmarkDirectory),
              let workspace = try? await workspacePool.fetchOrCreateWorkspace(workspaceURL: xcodeWorkspaceFileURL)
        else { return nil }
        let entrypoint = metadata.mapToEntrypoint(prefixing: benchmarkDirectory.path)
        let content: String = (try? String(contentsOf: entrypoint.fileURL, encoding: .utf8)) ?? ""
        
        let multiFileContextManager = MultiFileContextManager(
            workspaceProvider: ManualWorkspaceProvider(workspace: workspace),
            parser: SwiftProgrammingLanguageSyntaxParser()
        )
        let relevantSymbols: [SymbolContent] = await {
            if isMultiFileEnabledSubject.value {
                let symbols = await multiFileContextManager.retrieveRelevantSymbolsForFileContent(content: content)
                return Array(symbols.values)
            } else {
                return []
            }
        }()
        
        let suggestionRequest = SuggestionRequest(
            fileURL: entrypoint.fileURL,
            relativePath: entrypoint.fileURL.path.replacingOccurrences(of: benchmarkDirectory.path, with: ""),
            content: content,
            originalContent: content,
            lines: content.linesWithNewlineSuffix,
            cursorPosition: .init(line: entrypoint.cursor.line, character: entrypoint.cursor.character),
            cursorOffset: content.cursorOffset(line: entrypoint.cursor.line, character: entrypoint.cursor.character) ?? 0,
            tabSize: 4,
            indentSize: 4,
            usesTabsForIndentation: false,
            relevantCodeSnippets: relevantSymbols.mapToRelevantCodeSnippets()
        )
        let workspaceInfo = WorkspaceInfo(workspaceURL: xcodeWorkspaceFileURL, projectURL: benchmarkDirectory)
        let repository = OpenAICompletionRepository(config: .init())
        do {
            // only works when setting document version GitHubCopilotService to 0
            let suggestion = try await repository.structuredEdit(for: suggestionRequest)
//            let suggestions: [SuggestionBasic.CodeSuggestion]? = [exampleSuggestion]
            return .init(
                suggestion: suggestion.mapToCodeSuggestion(
                    requestPosition: SuggestionRequest.CursorPosition(
                        line: entrypoint.cursor.line,
                        character: entrypoint.cursor.character
                    )
                ),
                fileURL: entrypoint.fileURL,
                relevantSymbolsFromRequest: relevantSymbols
            )
        } catch {
            print("CK \(error)")
            return nil
        }
    }
    
    func applyCodeSuggestion(suggestion: SuggestionBasic.CodeSuggestion, at fileURL: URL) async {
        do {
            var content = try String(contentsOf: fileURL, encoding: .utf8)
            var lines = content.components(separatedBy: .newlines)

            let start = suggestion.range.start
            let end = suggestion.range.end

            // Check range bounds
            guard start.line < lines.count, end.line < lines.count else {
                print("Invalid range for suggestion in file: \(fileURL)")
                return
            }

            // Modify the content between start and end
            if start.line == end.line {
                var line = lines[start.line]
                let startIndex = line.index(line.startIndex, offsetBy: start.character)
                let endIndex = line.index(line.startIndex, offsetBy: end.character)
                line.replaceSubrange(startIndex..<endIndex, with: suggestion.text)
                lines[start.line] = line
            } else {
                // Multi-line replacement
                let startLine = lines[start.line]
                let endLine = lines[end.line]

                let startPrefix = String(startLine.prefix(start.character))
                let endSuffix = String(endLine.suffix(endLine.count - end.character))

                let replacementLines = suggestion.text.components(separatedBy: .newlines)

                // Replace the affected lines
                lines.replaceSubrange(start.line...end.line, with: [startPrefix + replacementLines.first!] +
                                      replacementLines.dropFirst().dropLast() +
                                      [replacementLines.last! + endSuffix])
            }

            let modifiedContent = lines.joined(separator: "\n")
            try modifiedContent.write(to: fileURL, atomically: true, encoding: .utf8)

            print("Applied suggestion to: \(fileURL.lastPathComponent)")
        } catch {
            print("Failed to apply suggestion to \(fileURL):", error)
        }
    }
    
    func storeContentInOutputDirectory(
        _ suggestion: SuggestionResponse,
        for taskNumber: Int,
        in benchmarkDirectory: BenchmarkDirectory
    ) async {
        guard let outputDirPath = await benchmarkSettingsRepository.outputDirectory.firstValue() else {
            print("Could not retrieve output directory.")
            return
        }
        let fileManager = FileManager.default
        
        let resolvedOutputDirPath = outputDirPath.replacingOccurrences(of: "~", with: fileManager.homeDirectoryForCurrentUser.path)
        let outputDir = URL(fileURLWithPath: resolvedOutputDirPath)
        
        var isDirectory: ObjCBool = false
        if !fileManager.fileExists(atPath: outputDir.path, isDirectory: &isDirectory) || !isDirectory.boolValue {
            do {
                try fileManager.createDirectory(at: outputDir, withIntermediateDirectories: true, attributes: nil)
            } catch {
                print("Failed to create output directory:", error)
                return
            }
        }
        
        var isBenchmarkDirADirectory: ObjCBool = false
        let outputBenchmarkDir = outputDir.appendingPathComponent(benchmarkDirectory.name, isDirectory: true)
        if !fileManager.fileExists(atPath: outputBenchmarkDir.path, isDirectory: &isBenchmarkDirADirectory) || !isBenchmarkDirADirectory.boolValue {
            do {
                try fileManager.createDirectory(at: outputBenchmarkDir, withIntermediateDirectories: true, attributes: nil)
            } catch {
                print("Failed to create output directory:", error)
                return
            }
        }
        
        let contextFolderName = isMultiFileEnabledSubject.value ? "with context" : "without context"
        let contextFolder = outputBenchmarkDir.appendingPathComponent(contextFolderName, isDirectory: true)
        if !fileManager.fileExists(atPath: contextFolder.path, isDirectory: &isDirectory) || !isDirectory.boolValue {
            do {
                try fileManager.createDirectory(at: contextFolder, withIntermediateDirectories: true, attributes: nil)
            } catch {
                print("Failed to create context directory:", error)
                return
            }
        }
        
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let reformattedTimestamp = timestamp.replacingOccurrences(of: ":", with: "-")
        let outputFileURL = contextFolder.appendingPathComponent("Task-\(taskNumber)-\(reformattedTimestamp).json")
        
        do {
            let dto = suggestion.toStoredDTO(timestamp: timestamp)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted]
            let data = try encoder.encode(dto)
            try data.write(to: outputFileURL)
            print("Stored suggestion at: \(outputFileURL.path)")
        } catch {
            print("Failed to write suggestion file:", error)
        }
    }
    
    func cleanUp() async {
        for (url, _) in await workspacePool.workspaces {
            await workspacePool.removeWorkspace(url: url)
        }
    }
    
    func readMetadata(at taskFolder: URL) -> MetadataDTO? {
        let metadataURL = taskFolder.appendingPathComponent("metadata.json")
        do {
            let data = try Data(contentsOf: metadataURL)
            
            let metadata = try JSONDecoder().decode(MetadataDTO.self, from: data)
            return metadata
        } catch {
            print("Failed to read metadata at \(metadataURL):", error)
            return nil
        }
    }
    
    func getTaskFolders(in rootDirectory: URL) -> [URL] {
        let fileManager = FileManager.default
        var taskFolders: [URL] = []

        let regex = try! NSRegularExpression(pattern: #"Task-\d+"#)

        let enumerator = fileManager.enumerator(at: rootDirectory, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles, .skipsPackageDescendants])

        while let fileURL = enumerator?.nextObject() as? URL {
            do {
                let resourceValues = try fileURL.resourceValues(forKeys: [.isDirectoryKey])
                if resourceValues.isDirectory == true {
                    let folderName = fileURL.lastPathComponent
                    let range = NSRange(location: 0, length: folderName.utf16.count)
                    if regex.firstMatch(in: folderName, options: [], range: range) != nil {
                        guard !fileURL.path.contains("/Tests/") else { continue }
                        taskFolders.append(fileURL)
                    }
                }
            } catch {
                print("Failed to read directory attributes for \(fileURL):", error)
            }
        }

        return taskFolders.sorted { lhs, rhs in
            let lhsNumber = extractTaskNumber(from: lhs.lastPathComponent) ?? 0
            let rhsNumber = extractTaskNumber(from: rhs.lastPathComponent) ?? 0
            return lhsNumber < rhsNumber
        }
    }
    
    private func extractTaskNumber(from name: String) -> Int? {
        let regex = try! NSRegularExpression(pattern: #"Task-(\d+)"#)
        let range = NSRange(location: 0, length: name.utf16.count)
        if let match = regex.firstMatch(in: name, options: [], range: range),
           let numberRange = Range(match.range(at: 1), in: name) {
            return Int(name[numberRange])
        }
        return nil
    }
    
    func findXcodeWorkspace(in directory: URL) -> URL? {
        let fileManager = FileManager.default
        let enumerator = fileManager.enumerator(at: directory, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles, .skipsPackageDescendants])

        while let fileURL = enumerator?.nextObject() as? URL {
            if fileURL.pathExtension == "xcworkspace" {
                return fileURL
            }
        }

        return nil
    }
    
    @MainActor
    func updateMultiFileContextState(_ newValue: Bool) {
        isMultiFileEnabledSubject.send(newValue)
    }
    
    @MainActor
    private func updateTaskStates(_ newValue: [TaskStatus]) {
        taskStatesSubject.send(newValue)
    }
    
    @MainActor
    private func updateTaskStatus(_ newValue: TaskStatus, at index: Int) {
        var updatedValue = taskStatesSubject.value
        updatedValue[index] = newValue
        taskStatesSubject.send(updatedValue)
    }
}

struct MetadataDTO: Codable {
    let taskId: Int
    let entrypoint: EntrypointDTO
    let files: [String]

    private enum CodingKeys: String, CodingKey {
        case taskId = "task_id"
        case entrypoint
        case files
    }
    
    struct EntrypointDTO: Codable {
        let filename: String
        let cursor: CursorPositionDTO
    }
    
    struct CursorPositionDTO: Codable {
        let line: Int
        let character: Int
    }
}

extension MetadataDTO {
    func mapToEntrypoint(prefixing baseUrl: String) -> EntryPoint {
        // Ensure there's exactly one "/" between the base and the filename
        let cleanedBase = baseUrl.hasSuffix("/") ? baseUrl : baseUrl + "/"
        let cleanedFilename = entrypoint.filename.hasPrefix("/") ? String(entrypoint.filename.dropFirst()) : entrypoint.filename
        let fullPath = cleanedBase + cleanedFilename

        return EntryPoint(
            cursor: CursorPosition(
                line: entrypoint.cursor.line,
                character: entrypoint.cursor.character
            ),
            fileURL: URL(fileURLWithPath: fullPath)
        )
    }
}

extension String {
    /// Splits the string by line and appends `\n` to each non-empty line
    var linesWithNewlineSuffix: [String] {
        self.split(separator: "\n", omittingEmptySubsequences: false)
            .map { String($0) + "\n" }
    }
    
    /// Calculates the character offset in the string from a line number and character index within that line
    func cursorOffset(line: Int, character: Int) -> Int? {
        let lines = self.split(separator: "\n", omittingEmptySubsequences: false)
        guard line < lines.count else { return nil }

        // Sum up the lengths of all previous lines (+1 for each '\n')
        let offsetBeforeLine = lines.prefix(line).reduce(0) { $0 + $1.count + 1 }
        
        // Ensure the character index doesn't exceed the current line length
        guard character <= lines[line].count else { return nil }

        return offsetBeforeLine + character
    }
}

let exampleSuggestion = SuggestionBasic.CodeSuggestion(
    id: "452c2f9a-c0e3-4a9e-8ae2-bf8babf5c634",
    text: "    func fetch() async { \n        do {\n            let page = try await useCase.fetch(request: request, page: 1)\n            movies = page.results\n        } catch {\n            errorToast.show()\n        }",
    position: .init(
        line: 27,
        character: 24
    ),
    range: .init(
        start: .init(
            line: 27,
            character: 0
        ),
        end: .init(
            line: 27,
            character: 24
        )
    )
)

struct SuggestionResponse {
    let suggestion: SuggestionBasic.CodeSuggestion
    let fileURL: URL
    let relevantSymbolsFromRequest: [SymbolContent]
}


extension AnyPublisher where Failure == Never {
    /// Awaits the first emitted value of the publisher (only for Failure == Never)
    func firstValue() async -> Output? {
        await withCheckedContinuation { continuation in
            var cancellable: AnyCancellable?
            cancellable = self.first().sink { value in
                continuation.resume(returning: value)
                cancellable?.cancel()
            }
        }
    }
}


struct StoredSuggestionDTO: Codable {
    let fileURL: String
    let id: String
    let suggestionText: String
    let position: CursorPositionDTO
    let range: CursorRangeDTO
    let createdAt: String
    let relevantSymbols: [RelevantSymbolsDTO]
    
    struct CursorPositionDTO: Codable {
        let line: Int
        let character: Int
    }
    
    struct CursorRangeDTO: Codable {
        let start: CursorPositionDTO
        let end: CursorPositionDTO
    }
    
    struct RelevantSymbolsDTO: Codable {
        let fileURL: String
        let name: String
        let content: String
        let startLine: Int
        let endLine: Int
        let kind: String
    }
}

extension SuggestionResponse {
    func toStoredDTO(timestamp: String) -> StoredSuggestionDTO {
        StoredSuggestionDTO(
            fileURL: fileURL.path,
            id: suggestion.id,
            suggestionText: suggestion.text,
            position: .init(
                line: suggestion.position.line,
                character: suggestion.position.character
            ),
            range: .init(
                start: .init(
                    line: suggestion.range.start.line,
                    character: suggestion.range.start.character
                ),
                end: .init(
                    line: suggestion.range.end.line,
                    character: suggestion.range.end.character
                )
            ),
            createdAt: timestamp,
            relevantSymbols: relevantSymbolsFromRequest.map { $0.toStoredDTO() }
        )
    }
}

extension SymbolContent {
    func toStoredDTO() -> StoredSuggestionDTO.RelevantSymbolsDTO {
        .init(
            fileURL: fileURL,
            name: symbol.name,
            content: content,
            startLine: symbol.startLine,
            endLine: symbol.endLine,
            kind: symbol.kind.rawValue
        )
    }
}

extension Array where Element == SymbolContent {
    func mapToRelevantCodeSnippets() -> [SuggestionProvider.RelevantCodeSnippet] {
        map { symbol in
                .init(
                    content: symbol.content,
                    priority: 0,
                    filePath: symbol.fileURL
                )
        }
    }
}

enum TaskStatus {
    case success
    case failure
    case notStarted
    case running
}



// MARK: - ChatGPT

import Foundation

// MARK: - Input models from your side

public struct SuggestionRequest: Sendable {
    
    public struct CursorPosition: Codable, Sendable {
        public var line: Int
        public var character: Int
    }

    public struct RelevantCodeSnippet: Codable, Sendable {
        public var path: String
        public var language: String?
        public var code: String
    }
    
    public var fileURL: URL
    public var relativePath: String
    public var content: String
    public var originalContent: String
    public var lines: [String]
    public var cursorPosition: CursorPosition
    public var cursorOffset: Int
    public var tabSize: Int
    public var indentSize: Int
    public var usesTabsForIndentation: Bool
    public var relevantCodeSnippets: [RelevantCodeSnippet]
}

// MARK: - Output

public struct CompletionSuggestion: Sendable {
    /// The raw text to insert at the cursor.
    public let insertText: String
    /// Optional reason the model stopped (e.g. "length", "stop").
    public let finishReason: String?
}

// MARK: - Protocol

public protocol CodeCompletionRepository: Sendable {
    /// Non-streaming variant that returns a single suggestion string.
//    func suggestion(
//        for request: SuggestionRequest
//    ) async throws -> CompletionSuggestion
    
    func structuredEdit(for request: SuggestionRequest) async throws -> CodeEdit
}

// MARK: - OpenAI implementation

public struct OpenAICompletionRepository: CodeCompletionRepository, Sendable {

    public enum OpenAIError: Error {
        case badResponse(status: Int, body: String)
        case decoding
        case emptyChoice
    }

    public struct Config: Sendable {
        public var apiKey: String
        /// e.g. "gpt-4o-mini"
        public var model: String
        /// Optional org header
        public var organization: String?
        /// API base, keep default unless using a proxy
        public var baseURL: URL

        public init(
            apiKey: String = "",
            model: String = "gpt-4o-mini",
            organization: String? = nil,
            baseURL: URL = URL(string: "https://api.openai.com/v1")!
        ) {
            self.apiKey = apiKey
            self.model = model
            self.organization = organization
            self.baseURL = baseURL
        }
    }

    private let config: Config
    private let urlSession: URLSession

    public init(config: Config, session: URLSession = .shared) {
        self.config = config
        self.urlSession = session
    }

    // MARK: Public API

//    public func suggestion(for request: SuggestionRequest) async throws -> CompletionSuggestion {
//        let url = config.baseURL.appendingPathComponent("chat/completions")
//        var req = URLRequest(url: url)
//        req.httpMethod = "POST"
//        req.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
//        if let org = config.organization { req.setValue(org, forHTTPHeaderField: "OpenAI-Organization") }
//        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
//
//        let payload = ChatPayload(
//            model: config.model,
//            messages: buildMessages(from: request),
//            temperature: 0,
//            stream: false,
//            response_format: nil  // No structured output requested
//        )
//        req.httpBody = try JSONEncoder().encode(payload)
//
//        let (data, resp) = try await urlSession.data(for: req)
//        guard let http = resp as? HTTPURLResponse else { throw OpenAIError.decoding }
//        guard 200..<300 ~= http.statusCode else {
//            let body = String(data: data, encoding: .utf8) ?? "<non-utf8>"
//            throw OpenAIError.badResponse(status: http.statusCode, body: body)
//        }
//
//        let decoded = try JSONDecoder().decode(ChatResponse.self, from: data)
//        guard let choice = decoded.choices.first else { throw OpenAIError.emptyChoice }
//        return CompletionSuggestion(
//            insertText: choice.message.content ?? "",
//            finishReason: choice.finishReason
//        )
//    }

    // MARK: - Prompt construction

    /// Builds a strict prompt that returns only the code to insert at <CURSOR>.
    private func buildMessages(from req: SuggestionRequest) -> [ChatMessage] {
        let indentDescriptor: String = {
            if req.usesTabsForIndentation { return "tabs=\(req.tabSize)" }
            return "spaces=\(req.indentSize)"
        }()

        // Surrounding context (prefix/suffix) based on cursorOffset
        let before = String(req.content.prefix(req.cursorOffset))
        let after = String(req.content.suffix(max(0, req.content.count - req.cursorOffset)))

        // Include some relevant separate snippets (e.g., related files / symbols)
        let related = req.relevantCodeSnippets.map { s in
            """
            PATH: \(s.path)
            LANG: \(s.language ?? "unknown")
            ----
            \(s.code)
            """
        }.joined(separator: "\n\n========\n\n")

        let system = ChatMessage(
            role: "system",
            content:
"""
You are a **code completion engine** integrated into Xcode IDE.
- The user sends source code with a <CURSOR> marker or with BEFORE/AFTER sections.
- Return **only** the code to insert at the cursor. **No prose, no fences, no echo**.
- Respect indentation (\(indentDescriptor)).
- Prefer short, compilable, context-aware continuations.
- Do not duplicate text already present in AFTER.
"""
        )

        let user = ChatMessage(
            role: "user",
            content:
"""
FILE: \(req.relativePath)

BEFORE:
«««
\(before)
»»»

< CURSOR >

AFTER:
«««
\(after)
»»»

RELEVANT CONTEXT (optional sections across the workspace):
«««
\(related)
»»»

Constraints:
- Output must be only the inserted code (no explanations).
- No changes can be made in RELEVANT CONTEXT.
- Do not repeat characters from AFTER.
- Keep indentation/style consistent with BEFORE.
"""
        )

        return [system, user]
    }

    // MARK: - SSE parsing

    private func parseDeltaChunk(jsonLine: String) throws -> String? {
        // Matches OpenAI stream schema for chat.completions:
        // { "id": "...","choices":[{"delta":{"content":"..."},"finish_reason":null,...}], ... }
        struct StreamEnvelope: Decodable {
            struct Choice: Decodable {
                struct Delta: Decodable { let content: String? }
                let delta: Delta
            }
            let choices: [Choice]
        }
        let data = Data(jsonLine.utf8)
        let env = try JSONDecoder().decode(StreamEnvelope.self, from: data)
        return env.choices.first?.delta.content
    }
}

public extension OpenAICompletionRepository {

    struct JSONOnly: Encodable { let type: String = "json_object" }

    public func structuredEdit(for request: SuggestionRequest) async throws -> CodeEdit {
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
        let lines = suggestion.components(separatedBy: "\n")
        let promptCodeLines = promptCode.components(separatedBy: "\n")
        let lineAfterCursor = promptCodeLines[line+1]
        if lineAfterCursor == lines.last {
            return lines.dropLast().joined(separator: "\n")
        } else {
            return suggestion
        }
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

// MARK: - OpenAI Shapes

private struct ChatPayload<RF: Encodable>: Encodable {
    let model: String
    let messages: [ChatMessage]
    let temperature: Double
    let stream: Bool
    let response_format: RF?
    init(model: String, messages: [ChatMessage], temperature: Double, stream: Bool, response_format: RF? = nil) {
        self.model = model
        self.messages = messages
        self.temperature = temperature
        self.stream = stream
        self.response_format = response_format
    }
}

private struct ChatMessage: Codable {
    let role: String
    let content: String
}

private struct ChatResponse: Decodable {
    struct Choice: Decodable {
        struct Message: Decodable { let role: String; let content: String? }
        let index: Int
        let message: Message
        let finishReason: String?

        private enum CodingKeys: String, CodingKey {
            case index, message
            case finishReason = "finish_reason"
        }
    }
    let id: String
    let choices: [Choice]
}


public struct CodeEdit: Codable, Sendable {
    public struct Position: Codable, Sendable {
        public let line: Int
        public let character: Int
    }
    public struct TextRange: Codable, Sendable {
        public let start: Position
        public let end: Position
    }
    
    /// Replacement text that MUST include the full (updated) content of the cursor's line.
    public let text: String
    public let range: TextRange
}

extension CodeEdit {
    func mapToSuggestionResponse(fileURL: URL, relevantSymbolsFromRequest: [SymbolContent]) -> SuggestionResponse {
        let start = range.start
        let end = range.end
        let range = SuggestionBasic.CursorRange(
            start: .init(line: start.line, character: start.character),
            end: .init(line: end.line, character: end.character)
        )
        let position = SuggestionBasic.CursorPosition(
            line: start.line,
            character: start.character
        )
        return SuggestionResponse(
            suggestion: SuggestionBasic.CodeSuggestion(
                id: UUID().uuidString,
                text: text,
                position: position,
                range: range
            ),
            fileURL: fileURL,
            relevantSymbolsFromRequest: relevantSymbolsFromRequest
        )
    }
}

extension Array where Element == SymbolContent {
    func mapToRelevantCodeSnippets() -> [SuggestionRequest.RelevantCodeSnippet] {
        map { symbol in
                .init(
                    path: symbol.fileURL,
                    language: "Swift",
                    code: symbol.content
                )
        }
    }
}

extension CodeEdit {
    func mapToCodeSuggestion(requestPosition: SuggestionRequest.CursorPosition) -> SuggestionBasic.CodeSuggestion {
        let start = range.start
        let end = range.end
        return SuggestionBasic.CodeSuggestion(
            id: UUID().uuidString,
            text: text,
            position: SuggestionBasic.CursorPosition(
                line: requestPosition.line,
                character: requestPosition.character
            ),
            range: SuggestionBasic.CursorRange(
                start: .init(line: start.line, character: start.character),
                end: .init(line: end.line, character: end.character)
            )
        )
    }
}

struct Greeter {
    func greet() {
        print("Hello")
    }
}
