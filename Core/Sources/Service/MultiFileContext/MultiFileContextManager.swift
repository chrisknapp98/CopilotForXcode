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
        let currentSymbol = parser.parse(file: file)
        let allSymbols = await classifyContentWithinFiles()
        var relevantSymbols: [String: SymbolContent] = [:]

        for (symbolName, symbolContent) in allSymbols {
            if file.content.contains(symbolName) {
                relevantSymbols[symbolName] = symbolContent
            }
        }
        
        let relevantSymbolsWithoutCurrentSymbol = relevantSymbols.filter { symbolName, symbolContent in
            if let currentSymbolName = currentSymbol.first?.symbol.name,
               currentSymbolName == symbolName { return false }
            
            let path = symbolContent.fileURL
            let ignored = ignoreWithinPaths.contains { pathToIgnore in path.contains(pathToIgnore) }
            return !ignored
        }
        return relevantSymbolsWithoutCurrentSymbol
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
