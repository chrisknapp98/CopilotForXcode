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

protocol BenchmarkManager {
    
}

class RealtimeSuggestionControllerBenchmarkManager: BenchmarkManager {
    private let benchmarkSettingsRepository: BenchmarkSettingsRepository
    @WorkspaceActor
    private let workspacePool: WorkspacePool
    private let scheduledCleaner: ScheduledCleaner
    
    init(benchmarkSettingsRepository: BenchmarkSettingsRepository) {
        @Dependency(\.workspacePool) var workspacePool
//        workspacePool.registerPlugin {
//            SuggestionServiceWorkspacePlugin(workspace: $0) { SuggestionService.service() }
//        }
        BuiltinExtensionManager.shared.setupExtensions([
            GitHubCopilotExtension(workspacePool: workspacePool)
        ])
//        scheduledCleaner = .init()
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
        self.scheduledCleaner = .init()
    }
    
    func getCodeSuggestions(at benchmarkDirectory: BenchmarkDirectory) async throws {
        let taskPaths: [URL] = getTaskFolders(in: benchmarkDirectory.url)
        for taskPath in taskPaths.prefix(1) {
            if let suggestion = await getCodeSuggestionFromService(at: taskPath, from: benchmarkDirectory.url) {
                await applyCodeSuggestion(suggestion: suggestion.suggestion, at: suggestion.fileURL)
            }
            
        }
    }
    
    func getCodeSuggestionFromService(at directory: URL, from benchmarkDirectory: URL) async -> SuggestionResponse? {
        guard let metadata: MetadataDTO = readMetadata(at: directory) else { return nil }
        let entrypoint = metadata.mapToEntrypoint(prefixing: benchmarkSettingsRepository.projectRootURL)
        let tuple: (workspace: Workspace, filespace: Filespace)? = try? await workspacePool.fetchOrCreateWorkspaceAndFilespace(fileURL: entrypoint.fileURL)
        guard let workspace = tuple?.workspace,
//              let filespace = try? await workspace.createFilespaceIfNeeded(fileURL: entrypoint.fileURL)
              let filespace = tuple?.filespace
        else {
            return nil
        }
//        workspace.
        await filespace.reset()
        await cleanUp()
        await workspace.didOpenFilespace(filespace)
//        await filespace.bumpVersion()
        let content: String = (try? String(contentsOf: entrypoint.fileURL, encoding: .utf8)) ?? ""
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
        // TODO: use the broader one
        let workspaceInfo = WorkspaceInfo(workspaceURL: benchmarkDirectory, projectURL: benchmarkDirectory)
        do {
            // only works when setting document version GitHubCopilotService to 0
//            let suggestions = try await workspace.suggestionService?.getSuggestions(suggestionRequest, workspaceInfo: workspaceInfo)
            let suggestions: [SuggestionBasic.CodeSuggestion]? = [exampleSuggestion]
            await workspace.closeFilespace(fileURL: URL(fileURLWithPath: metadata.entrypoint.filename))
            guard let suggestions, let firstSuggestion = suggestions.first else { return nil }
            return .init(
                suggestion: firstSuggestion,
                fileURL: entrypoint.fileURL
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
    
    public func cleanUp() async {
//        guard let service else { return }

        let workspaceInfos = XcodeInspector.shared.xcodes.reduce(
            into: [
                XcodeAppInstanceInspector.WorkspaceIdentifier:
                    XcodeAppInstanceInspector.WorkspaceInfo
            ]()
        ) { result, xcode in
            let infos = xcode.realtimeWorkspaces
            for (id, info) in infos {
                if let existed = result[id] {
                    result[id] = existed.combined(with: info)
                } else {
                    result[id] = info
                }
            }
        }
        for (url, workspace) in await workspacePool.workspaces {
            if workspace.isExpired, workspaceInfos[.url(url)] == nil {
//                Logger.service.info("Remove idle workspace")
                await workspace.cleanUp(availableTabs: [])
                await workspacePool.removeWorkspace(url: url)
            } else {
                let tabs = (workspaceInfos[.url(url)]?.tabs ?? [])
                    .union(workspaceInfos[.unknown]?.tabs ?? [])
                // cleanup workspace
                await workspace.cleanUp(availableTabs: tabs)
            }
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
        EntryPoint(
            cursor: CursorPosition(
                line: entrypoint.cursor.line,
                character: entrypoint.cursor.character
            ),
            fileURL: URL(fileURLWithPath: baseUrl+entrypoint.filename)
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
}
