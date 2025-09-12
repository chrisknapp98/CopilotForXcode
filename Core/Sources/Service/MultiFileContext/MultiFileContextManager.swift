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
    public func listFilesInWorkspace(ignoreWithinPaths: [String]) async -> [String] {
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
                        if ignoreWithinPaths.contains(where: { fileURL.absoluteString.contains($0) }) { continue }
                        files.append(fileURL.absoluteString)
                    }
                } catch { print(error, fileURL) }
            }
        }
        return files
    }
    
    public func readFileContents(ignoreWithinPaths: [String]) async -> [FileContent] {
        let workspaceURLs = await listFilesInWorkspace(ignoreWithinPaths: ignoreWithinPaths)
        let fileURLs = workspaceURLs
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
    
    public func classifyContentWithinFiles(files: [FileContent]) async -> [String: SymbolContent] {
        var result: [String: SymbolContent] = [:]

        for file in files {
            var symbols = parser.parse(file: file)
            mergeExtensionsIntoBaseDeclarations(&symbols)
            for symbol in symbols {
                result[symbol.symbol.name] = symbol
            }
        }

        return result
    }
    
    private func readFile(_ urlString: String) -> FileContent? {
        guard let url = URL(string: urlString) else { return nil }
        guard let content = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        return FileContent(fileURL: urlString, content: content)
    }

    public func expandRelevantSymbols(
        from root: FileContent,
        ignoreWithinPaths: [String] = [],
        maxDepth: Int? = nil,
        maxFiles: Int? = nil
    ) async -> RelevantSymbolsSummary {
        @inline(__always)
        func isIgnored(_ url: String) -> Bool {
            ignoreWithinPaths.contains { url.contains($0) }
        }

        let start = Date()

        let level0 = await retrieveRelevantSymbolsForFileContent(file: root, ignoreWithinPaths: ignoreWithinPaths)
        var level0Unique: [SymbolContent] = []
        var includedFiles = Set<String>()
        for s in level0.values {
            if includedFiles.insert(s.fileURL).inserted {
                level0Unique.append(s)
            }
        }
        var levels: [[SymbolContent]] = [level0Unique]

        var visited = Set<String>([root.fileURL])
        var depth = 0
        var remainingFiles = maxFiles

        while maxDepth == nil || depth < maxDepth! {
            let prev = levels.last ?? []
            var nextURLs = Set(prev.map(\.fileURL))
            nextURLs.subtract(visited)
            nextURLs = nextURLs.filter { !isIgnored($0) }

            if nextURLs.isEmpty { break }

            if let remaining = remainingFiles, nextURLs.count > remaining {
                nextURLs = Set(nextURLs.prefix(remaining))
            }

            var rawNextLevel: [SymbolContent] = []
            for url in nextURLs {
                visited.insert(url)
                guard let fc = readFile(url) else { continue }
                let dict = await retrieveRelevantSymbolsForFileContent(file: fc, ignoreWithinPaths: ignoreWithinPaths)
                rawNextLevel.append(contentsOf: dict.values)
            }

            var nextLevel: [SymbolContent] = []
            var seenThisLevel = Set<String>()
            for s in rawNextLevel {
                guard !includedFiles.contains(s.fileURL) else { continue }
                if seenThisLevel.insert(s.fileURL).inserted {
                    nextLevel.append(s)
                }
            }

            if nextLevel.isEmpty { break }

            includedFiles.formUnion(nextLevel.map(\.fileURL))

            levels.append(nextLevel)
            depth += 1

            if remainingFiles != nil {
                remainingFiles! -= nextURLs.count
                if remainingFiles! <= 0 { break }
            }
        }

        return RelevantSymbolsSummary(
            symbolsAtLevel: levels,
            durationInSeconds: Date().timeIntervalSince(start)
        )
    }
    
    public func retrieveRelevantSymbolsForFileContent(
        file: FileContent,
        ignoreWithinPaths: [String] = []
    ) async -> [String: SymbolContent] {
        let currentSymbolName = parser.parse(file: file).first?.symbol.name
        let files = await readFileContents(ignoreWithinPaths: ignoreWithinPaths)
        let allSymbols = await classifyContentWithinFiles(files: files)

        var relevant: [String: SymbolContent] = [:]

        for (name, content) in allSymbols {
            if let current = currentSymbolName, current == name { continue }

            if file.content.containsExactIdentifier(name) {
                if relevant[name] == nil {
                    relevant[name] = content
                }
            }
        }
        
        let usedDependencyKeys = await retrieveUsedDependencyKeys(file: file, allFiles: files)
        for dependency in usedDependencyKeys {
            if let content = allSymbols[dependency.symbolName], !relevant.keys.contains(dependency.symbolName) {
                relevant[dependency.symbolName] = content
            }
        }

        return relevant
    }
    
    private func retrieveUsedDependencyKeys(file: FileContent, allFiles: [FileContent]) async -> [RegisteredDependencyValue] {
        let dependencyValuesExtensions = await scanProjectForDependencyKeys(files: allFiles)
        let dependecyVariablesAndTypes = dependencyValuesExtensions.flatMap { getDependencySymbolsFromExtensionContent($0.symbol.content) }
        let usedDependencyKeys = file.content.extractDependencyReferences(dependencies: dependecyVariablesAndTypes)
        return usedDependencyKeys
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
    
    private func scanProjectForDependencyKeys(files: [FileContent]) async -> [SymbolContent] {
        let allSymbols: [SymbolContent] = files.flatMap { parser.parse(file: $0) }
        let dependencyValueExtensions = allSymbols.filter {
            $0.symbol.kind == .extensionWord && $0.symbol.name == "DependencyValues"
        }
        return dependencyValueExtensions
    }

    /// Extract every `var <prop>: <Type> { ... }` and/or `self[<Type>.self]` from an
    /// `extension DependencyValues { ... }` source string.
    private func getDependencySymbolsFromExtensionContent(_ content: String) -> [RegisteredDependencyValue] {
        var results = Set<RegisteredDependencyValue>()

        // 1) Typed property form: `var fooBar: TypeName {`
        if let typed = try? NSRegularExpression(
            pattern: #"\bvar\s+([A-Za-z_][A-Za-z0-9_]*)\s*:\s*([A-Za-z_][A-Za-z0-9_?.<>]+)\s*\{"#,
            options: []
        ) {
            let range = NSRange(content.startIndex..., in: content)
            typed.enumerateMatches(in: content, options: [], range: range) { m, _, _ in
                guard
                    let m,
                    let nameR = Range(m.range(at: 1), in: content),
                    let typeR = Range(m.range(at: 2), in: content)
                else { return }
                let varName = String(content[nameR])
                let typeName = String(content[typeR])
                results.insert(.init(variableName: varName, symbolName: typeName))
            }
        }

        return Array(results)//.flatMap { $0 }
    }
}

extension String {
    /// Checks if the string contains an exact symbol match.
    /// Allows any character besides letters, numbers, and underscores as boundaries
    func containsExactIdentifier(_ name: String) -> Bool {
        guard !name.isEmpty else { return false }
        
        @inline(__always)
        func isIdentChar(_ c: Character) -> Bool { c.isLetter || c.isNumber || c == "_" }
        
        var search = startIndex..<endIndex
        while let range = self.range(of: name, options: .literal, range: search) {
            let before = (range.lowerBound == startIndex) ? nil : self[index(before: range.lowerBound)]
            let after  = (range.upperBound == endIndex)   ? nil : self[range.upperBound]
            
            let boundaryBefore = before.map { !isIdentChar($0) && $0 != "." } ?? true
            let boundaryAfter  = after.map  { !isIdentChar($0) } ?? true
            
            if boundaryBefore && boundaryAfter {
                return true
            }
            search = range.upperBound..<endIndex
        }
        return false
    }
    
    /// Extracts the DependencyValues used in this source file by scanning for
    /// `@Dependency(\.<key>)` and returning the matching entries from `dependencies`.
    /// - Returns: Ordered, de-duplicated list of RegisteredDependencyValue, in order of first appearance.
    func extractDependencyReferences(dependencies: [RegisteredDependencyValue]) -> [RegisteredDependencyValue] {
        // Build quick lookup: variableName -> RegisteredDependencyValue
        let byName = Dictionary(uniqueKeysWithValues: dependencies.map { ($0.variableName, $0) })

        // Regex: @Dependency(\.fooBar)
        let pattern = #"@Dependency\s*\(\s*\\\.\s*([A-Za-z_][A-Za-z0-9_]*)\s*\)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return [] }

        let ns = self as NSString
        let range = NSRange(location: 0, length: ns.length)

        // Collect (key, location) to preserve order; de-dupe by key
        var seen = Set<String>()
        var orderedKeys: [(key: String, location: Int)] = []

        regex.enumerateMatches(in: self, options: [], range: range) { match, _, _ in
            guard
                let match,
                match.numberOfRanges >= 2
            else { return }
            let keyRange = match.range(at: 1)
            guard keyRange.location != NSNotFound else { return }
            let key = ns.substring(with: keyRange)
            if !seen.contains(key) {
                seen.insert(key)
                orderedKeys.append((key, match.range.location))
            }
        }

        // Sort by first occurrence in the file
        orderedKeys.sort { $0.location < $1.location }

        // Map to known dependencies; unknown keys are ignored
        return orderedKeys.compactMap { byName[$0.key] }
    }
}
