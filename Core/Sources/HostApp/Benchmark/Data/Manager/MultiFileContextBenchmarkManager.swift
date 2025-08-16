import Foundation
import Combine
import Dependencies
import Workspace
import Service
import SuggestionBasic
import SuggestionProvider
import SuggestionService
import WorkspaceSuggestionService
import CopilotForXcodeKit
import BuiltinExtension
import GitHubCopilotService

class MultiFileContextBenchmarkManager: BenchmarkManager {
    private let benchmarkSettingsRepository: BenchmarkSettingsRepository
    @WorkspaceActor
    private let workspacePool: WorkspacePool
    
    private let isMultiFileEnabledSubject = CurrentValueSubject<Bool, Never>(true)
    var isMultiFileEnabled: AnyPublisher<Bool, Never> {
        isMultiFileEnabledSubject.eraseToAnyPublisher()
    }
    private let taskStatesSubject = CurrentValueSubject<[BenchmarkDirectory: [TaskStatus]], Never>([:])
    var taskStates: AnyPublisher<[BenchmarkDirectory: [TaskStatus]], Never> {
        taskStatesSubject.eraseToAnyPublisher()
    }
    private var openAIKey: String?
    private let selectedGenAIModelSubject = CurrentValueSubject<GenAILanguageModel, Never>(.defaultModel)
    var selectedGenAIModel: AnyPublisher<GenAILanguageModel, Never> {
        selectedGenAIModelSubject.eraseToAnyPublisher()
    }
    private var cancellables = Set<AnyCancellable>()
    
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
        
        benchmarkSettingsRepository.benchmarkDirectories.sink { [weak self] benchmarkDirectories in
            for directory in benchmarkDirectories {
                guard let taskPaths: [URL] = self?.getTaskFolders(in: directory.url) else {
                    return
                }
                let initialTaskStates = taskPaths.map { _ in TaskStatus.notStarted }
                Task { await self?.updateTaskStates(in: directory, newValue: initialTaskStates) }
            }
        }.store(in: &cancellables)
        
        benchmarkSettingsRepository.openAIKey.sink { [weak self] key in
            self?.openAIKey = key
        }.store(in: &cancellables)
    }
    
    func getCodeSuggestions(at benchmarkDirectory: BenchmarkDirectory) async throws {
        let taskPaths: [URL] = getTaskFolders(in: benchmarkDirectory.url)
        let initialTaskStates = taskPaths.map { _ in TaskStatus.scheduled }
        await updateTaskStates(in: benchmarkDirectory, newValue: initialTaskStates)
        for (index, _) in taskPaths.prefix(1).enumerated() {
            await runTask(at: index, in: benchmarkDirectory)
            try await Task.sleep(nanoseconds: 3_000_000_000)
        }
    }
    
    private func getCodeSuggestionFromService(at directory: URL, from benchmarkDirectory: URL) async -> SuggestionResponse? {
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
            let suggestions = try await workspace.suggestionService?.getSuggestions(suggestionRequest, workspaceInfo: workspaceInfo)
            await saveFilespace(entrypoint: entrypoint, in: workspace)
            await closeFilespaces(entrypoint: entrypoint, relevantSymbols: relevantSymbols, in: workspace)
            guard let suggestions, let firstSuggestion = suggestions.first else { return nil }
            return .init(
                suggestion: firstSuggestion,
                fileURL: entrypoint.fileURL,
                relevantSymbolsFromRequest: relevantSymbols,
                model: selectedGenAIModelSubject.value
            )
        } catch {
            return nil
        }
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
    
    func runTask(at index: Int, in benchmarkDirectory: BenchmarkDirectory) async {
        let taskPath = getTaskFolders(in: benchmarkDirectory.url)[index]
        await updateTaskStatus(in: benchmarkDirectory, state: .running, at: index)
        if case .githubCopilot = selectedGenAIModelSubject.value,
           let suggestion = await getCodeSuggestionFromService(at: taskPath, from: benchmarkDirectory.url) {
            await applyCodeSuggestion(suggestion: suggestion.suggestion, at: suggestion.fileURL)
            await storeContentInOutputDirectory(suggestion, for: index+1, in: benchmarkDirectory)
            await updateTaskStatus(in: benchmarkDirectory, state: .success, at: index)
        } else if let openAIKey = openAIKey,
           case let .openAI(model) = selectedGenAIModelSubject.value,
           let suggestion = await getCodeSuggestionFromOpenAI(
            at: taskPath,
            from: benchmarkDirectory.url,
            key: openAIKey,
            model: model.rawValue
           ) {
            await applyCodeSuggestion(suggestion: suggestion.suggestion, at: suggestion.fileURL)
            await storeContentInOutputDirectory(suggestion, for: index+1, in: benchmarkDirectory)
            await updateTaskStatus(in: benchmarkDirectory, state: .success, at: index)
        } else {
            await updateTaskStatus(in: benchmarkDirectory, state: .failure, at: index)
        }
        await cleanUp()
    }
    
    private func getCodeSuggestionFromOpenAI(at directory: URL, from benchmarkDirectory: URL, key: String, model: String) async -> SuggestionResponse? {
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
        let repository = OpenAICompletionRepository(config: .init(apiKey: key, model: model))
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
                relevantSymbolsFromRequest: relevantSymbols,
                model: selectedGenAIModelSubject.value
            )
        } catch {
            print("CK \(error)")
            return nil
        }
    }
    
    private func applyCodeSuggestion(suggestion: SuggestionBasic.CodeSuggestion, at fileURL: URL) async {
        do {
            let content = try String(contentsOf: fileURL, encoding: .utf8)
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
    
    private func storeContentInOutputDirectory(
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
    
    private func cleanUp() async {
        for (url, _) in await workspacePool.workspaces {
            await workspacePool.removeWorkspace(url: url)
        }
    }
    
    private func readMetadata(at taskFolder: URL) -> MetadataDTO? {
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
    
    private func getTaskFolders(in rootDirectory: URL) -> [URL] {
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
    
    private func findXcodeWorkspace(in directory: URL) -> URL? {
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
    func changeGenAIModel(to newModel: GenAILanguageModel) {
        selectedGenAIModelSubject.send(newModel)
    }
    
    @MainActor
    func updateMultiFileContextState(_ newValue: Bool) {
        isMultiFileEnabledSubject.send(newValue)
    }
    
    @MainActor
    private func updateTaskStates(in directory: BenchmarkDirectory, newValue: [TaskStatus]) {
        var currentStates = taskStatesSubject.value
        currentStates[directory] = newValue
        taskStatesSubject.send(currentStates)
    }
    
    @MainActor
    private func updateTaskStatus(in directory: BenchmarkDirectory, state: TaskStatus, at index: Int) {
        var currentStates = taskStatesSubject.value
        guard var currentStatesInDirectory = currentStates[directory] else { return }
        currentStatesInDirectory[index] = state
        currentStates[directory] = currentStatesInDirectory
        taskStatesSubject.send(currentStates)
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
            relevantSymbols: relevantSymbolsFromRequest.map { $0.toStoredDTO() },
            model: model.id
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
