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
        for (index, taskPath) in taskPaths.prefix(1).enumerated() {
            if let suggestion = await getCodeSuggestionFromService(at: taskPath, from: benchmarkDirectory.url) {
                await applyCodeSuggestion(suggestion: suggestion.suggestion, at: suggestion.fileURL)
                await storeContentInOutputDirectory(suggestion, for: index+1, in: benchmarkDirectory)
            }
            
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
        let relevantSymbols = await multiFileContextManager.retrieveRelevantSymbolsForFileContent(content: content)
        
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
            relevantCodeSnippets: []
        )
        let workspaceInfo = WorkspaceInfo(workspaceURL: xcodeWorkspaceFileURL, projectURL: benchmarkDirectory)
        do {
            // only works when setting document version GitHubCopilotService to 0
            let suggestions = try await workspace.suggestionService?.getSuggestions(suggestionRequest, workspaceInfo: workspaceInfo)
//            let suggestions: [SuggestionBasic.CodeSuggestion]? = [exampleSuggestion]
            await workspace.closeFilespace(fileURL: URL(fileURLWithPath: metadata.entrypoint.filename))
            guard let suggestions, let firstSuggestion = suggestions.first else { return nil }
            return .init(
                suggestion: firstSuggestion,
                fileURL: entrypoint.fileURL,
                relevantSymbolsFromRequest: Array(relevantSymbols.values)
            )
        } catch {
            print("CK \(error)")
            return nil
        }
//        return nil
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
        
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let reformattedTimestamp = timestamp.replacingOccurrences(of: ":", with: "-")
        let outputFileURL = outputBenchmarkDir.appendingPathComponent("Task-\(taskNumber)-\(reformattedTimestamp).json")
        
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
                        taskFolders.append(fileURL)
                    }
                }
            } catch {
                print("Failed to read directory attributes for \(fileURL):", error)
            }
        }

        return taskFolders.sorted(by: { $0.lastPathComponent < $1.lastPathComponent })
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
