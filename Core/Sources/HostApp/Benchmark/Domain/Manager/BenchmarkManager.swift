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
    }
    
    func getCodeSuggestions(at benchmarkDirectory: BenchmarkDirectory) async throws {
        let taskPaths: [URL] = getTaskFolders(in: benchmarkDirectory.url)
        for taskPath in taskPaths {
            let suggestion = await getCodeSuggestionFromService(at: taskPath, from: benchmarkDirectory.url)
        }
    }
    
    func getCodeSuggestionFromService(at directory: URL, from benchmarkDirectory: URL) async -> SuggestionBasic.CodeSuggestion? {
        guard let metadata: MetadataDTO = readMetadata(at: directory) else { return nil }
        let entrypoint = metadata.mapToEntrypoint(prefixing: benchmarkSettingsRepository.projectRootURL)
        let tuple: (workspace: Workspace, _: Filespace)? = try? await workspacePool.fetchOrCreateWorkspaceAndFilespace(fileURL: entrypoint.fileURL)
        guard let workspace = tuple?.workspace,
              let filespace = try? await workspace.createFilespaceIfNeeded(fileURL: entrypoint.fileURL)
        else {
            return nil
        }
        await workspace.didOpenFilespace(filespace)
        await filespace.bumpVersion()
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
            let suggestions = try await workspace.suggestionService?.getSuggestions(suggestionRequest, workspaceInfo: workspaceInfo)
            return suggestions?.first
        } catch {
            print("CK \(error)")
            return nil
        }
//        return nil
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
