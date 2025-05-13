import Foundation
import Workspace
import XcodeInspector

class MultiFileContextManager {
    let workspaceProvider: WorkspaceProvider
    
    init(workspaceProvider: WorkspaceProvider) {
        self.workspaceProvider = workspaceProvider
    }
    
    /// List files within workspace recursively
    /// Retrieved from: https://stackoverflow.com/a/57640445
    func listFilesInWorkspace() async -> [String] {
        guard let workspace: Workspace = try? await workspaceProvider.workspace()
        else { return [] }
        var files = [String]()
        if let enumerator = FileManager.default.enumerator(at: workspace.projectRootURL, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles, .skipsPackageDescendants]) {
            for case let fileURL as URL in enumerator {
                do {
                    let fileAttributes = try fileURL.resourceValues(forKeys: [.isRegularFileKey])
                    if fileAttributes.isRegularFile! {
                        files.append(fileURL.absoluteString)
                    }
                } catch { print(error, fileURL) }
            }
        }
        return files
    }
    
    func readFileContents() async -> [FileContent] {
        let fileURLs = await listFilesInWorkspace()
        return fileURLs.compactMap { fileURLString in
            guard let fileURL = URL(string: fileURLString) else { return nil }
            do {
                let content = try String(contentsOf: fileURL, encoding: .utf8)
                return FileContent(fileURL: fileURLString, content: content)
            } catch {
                print("Failed to read \(fileURL):", error)
                return nil
            }
        }
    }
}

struct FileContent {
    let fileURL: String
    let content: String
}
