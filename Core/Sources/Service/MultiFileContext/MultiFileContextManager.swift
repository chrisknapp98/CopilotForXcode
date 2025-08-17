import Foundation

public class MultiFileContextManager {
    private let workspaceProvider: WorkspaceProvider
    private let parser: ProgrammingLanguageSyntaxParser
    
    public init(workspaceProvider: WorkspaceProvider, parser: ProgrammingLanguageSyntaxParser) {
        self.workspaceProvider = workspaceProvider
        self.parser = parser
    }
    
    /// List files within workspace recursively
    /// Retrieved from: https://stackoverflow.com/a/57640445
    public func listFilesInWorkspace() async -> [String] {
        guard let workspaceURL = try? await workspaceProvider.getProjectRootURL()
        else { return [] }
        var files = [String]()
        if let enumerator = FileManager.default.enumerator(
            at: workspaceURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) {
            for case let fileURL as URL in enumerator {
                do {
                    let fileAttributes = try fileURL.resourceValues(forKeys: [.isRegularFileKey])
                    if fileAttributes.isRegularFile ?? false, fileURL.pathExtension.lowercased() == "swift" {
                        files.append(fileURL.absoluteString)
                    }
                } catch { print(error, fileURL) }
            }
        }
        return files
    }
    
    public func readFileContents() async -> [FileContent] {
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
    
    public func classifyContentWithinFiles() async -> [String: SymbolContent] {
        let fileContents = await readFileContents()
        var result: [String: SymbolContent] = [:]

        for file in fileContents {
            var symbols = parser.parse(file: file)
            mergeExtensionsIntoBaseDeclarations(&symbols)
            for symbol in symbols {
                result[symbol.symbol.name] = symbol
            }
        }

        return result
    }
    
    public func retrieveRelevantSymbolsForFileContent(
        file: FileContent,
        ignoreWithinPaths: [String] = []
    ) async -> [String: SymbolContent] {
        let currentSymbolName = parser.parse(file: file).first?.symbol.name
        let allSymbols = await classifyContentWithinFiles()

        var relevant: [String: SymbolContent] = [:]

        for (name, content) in allSymbols {
            if let current = currentSymbolName, current == name { continue }
            if ignoreWithinPaths.contains(where: { content.fileURL.contains($0) }) { continue }

            if file.content.containsExactIdentifier(name) {
                if relevant[name] == nil {
                    relevant[name] = content
                }
            }
        }

        return relevant
    }
    
    private func mergeExtensionsIntoBaseDeclarations(_ symbols: inout [SymbolContent]) {
        var indexesToRemove: [Int] = []

        for (index, symbol) in symbols.enumerated() {
            guard symbol.symbol.kind == .extensionWord else { continue }

            if let targetIndex = symbols.firstIndex(where: {
                $0.symbol.name == symbol.symbol.name &&
                $0.symbol.kind != .extensionWord
            }) {
                var target = symbols[targetIndex]
                target.symbol.extensions.append(symbol)
                symbols[targetIndex] = target

                indexesToRemove.append(index)
            }
        }

        for index in indexesToRemove.sorted(by: >) {
            symbols.remove(at: index)
        }
    }
    
}

extension String {
    /// Allow any character besides letters, numbers, and underscores as boundaries
    func containsExactIdentifier(_ name: String) -> Bool {
        guard !name.isEmpty else { return false }

        @inline(__always)
        func isIdentChar(_ c: Character) -> Bool { c.isLetter || c.isNumber || c == "_" }

        var search = startIndex..<endIndex
        while let range = self.range(of: name, options: .literal, range: search) {
            let before = (range.lowerBound == startIndex) ? nil : self[index(before: range.lowerBound)]
            let after  = (range.upperBound == endIndex)   ? nil : self[range.upperBound]

            let boundaryBefore = before.map { !isIdentChar($0) } ?? true
            let boundaryAfter  = after.map  { !isIdentChar($0) } ?? true

            if boundaryBefore && boundaryAfter {
                return true
            }
            search = range.upperBound..<endIndex
        }
        return false
    }
}
