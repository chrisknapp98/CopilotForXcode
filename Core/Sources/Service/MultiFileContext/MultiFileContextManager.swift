import Foundation

public class MultiFileContextManager {
    private let workspaceProvider: WorkspaceProvider
    private let parser: ProgrammingLanguageSyntaxParser
    
    // cache so we don’t re-parse the file every time
//    private var cachedSwiftDependenciesKeys: [String: String]?
    
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
    
    /// List files within dependency directories
    /// This is currently not used as it is too expensive to run
//    private func listDependencyFiles() async -> [String] {
//        guard let root = try? await workspaceProvider.getProjectRootURL() else { return [] }
//        var files: [String] = []
//        let fm = FileManager.default
//        let depRoots: [URL] = [
//            root.appendingPathComponent("Tuist/.build/checkouts", isDirectory: true),
//            root.appendingPathComponent("SourcePackages/checkouts", isDirectory: true),
//            root.appendingPathComponent(".swiftpm/xcode/checkout", isDirectory: true)
//        ].filter { fm.fileExists(atPath: $0.path) }
//        
//        for base in depRoots {
//            if let e = fm.enumerator(
//                at: base,
//                includingPropertiesForKeys: [.isRegularFileKey],
//                options: [.skipsPackageDescendants]   // keep this to avoid .xcodeproj/.app bundles
//            ) {
//                for case let url as URL in e {
//                    guard url.pathExtension.lowercased() == "swift" else { continue }
//                    // (Optional) only Sources, to avoid Tests/Examples
//                    // guard url.path.contains("/Sources/") else { continue }
//                    files.append(url.absoluteString)
//                }
//            }
//        }
//        return files
//    }
    
    /// Looks up `swift-dependencies/Sources/Dependencies/DependencyValues.swift`
    /// under common checkout roots relative to the workspace.
//    func loadSwiftDependenciesDependencyValuesFile() async throws -> [String: String] {
//        guard let root = try? await workspaceProvider.getProjectRootURL() else { return [:] }
//        
//        // candidate locations (Tuist SPM, Xcode SPM, .swiftpm)
//        let candidates: [URL] = [
//            root.appendingPathComponent("Tuist/.build/checkouts/swift-dependencies/Sources/Dependencies/DependencyValues.swift"),
//            root.appendingPathComponent("SourcePackages/checkouts/swift-dependencies/Sources/Dependencies/DependencyValues.swift"),
//            root.appendingPathComponent(".swiftpm/xcode/checkout/swift-dependencies/Sources/Dependencies/DependencyValues.swift"),
//        ]
//        
//        let fm = FileManager.default
//        guard let fileURL = candidates.first(where: { fm.fileExists(atPath: $0.path) }) else {
//            return [:]
//        }
//        
//        let src = try String(contentsOf: fileURL, encoding: .utf8)
//        return parseDependencyValuesSource(src)
//    }
    
    public func readFileContents(ignoreWithinPaths: [String]) async -> [FileContent] {
        let workspaceURLs = await listFilesInWorkspace(ignoreWithinPaths: ignoreWithinPaths)
//        let dependencyURLs = await listDependencyFiles()
        let fileURLs = workspaceURLs // + dependencyURLs
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
//            if ignoreWithinPaths.contains(where: { content.fileURL.contains($0) }) { continue }

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
    
    func retrieveUsedDependencyKeys(file: FileContent, allFiles: [FileContent]) async -> [RegisteredDependencyValue] {
        let dependencyValuesExtensions = await scanProjectForDependencyKeys(files: allFiles)
        let dependecyVariablesAndTypes = dependencyValuesExtensions.flatMap { getDependencySymbolsFromExtensionContent($0.symbol.content) }
        let usedDependencyKeys = file.content.extractDependencyReferences(dependencies: dependecyVariablesAndTypes)
        return usedDependencyKeys
    }
        
    
//    public func retrieveRelevantSymbolsForFileContent(
//        file: FileContent,
//        ignoreWithinPaths: [String] = []
//    ) async -> [String: SymbolContent] {
//        let currentSymbolName = parser.parse(file: file).first?.symbol.name
//        let allSymbols = await classifyContentWithinFiles()
//        
//        // Build maps
//        let propToType = await collectDependencyValueKeys(from: allSymbols)        // "errorToastCoordinator" -> "ErrorToastCoordinator"
//        let usedKeys   = extractDependencyKeys(in: file.content)              // e.g. {"errorToastCoordinator"}
//        
//        // Invert for quick lookup: type -> set of keys
//        var keysByType: [String: Set<String>] = [:]
//        for (prop, type) in propToType { keysByType[type, default: []].insert(prop) }
//        
//        var relevant: [String: SymbolContent] = [:]
//        
//        for (typeName, content) in allSymbols {
//            if let current = currentSymbolName, current == typeName { continue }
//            if ignoreWithinPaths.contains(where: { content.fileURL.contains($0) }) { continue }
//            
//            var isReferenced = file.content.containsExactIdentifier(typeName)
//            if !isReferenced, let keys = keysByType[typeName], !usedKeys.isDisjoint(with: keys) {
//                isReferenced = true
//            }
//            
//            if isReferenced { relevant[typeName] = content }
//        }
//        
//        return relevant
//    }
    
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
    
    /// Parses the DependencyValues.swift source and returns property -> type mapping.
//    func parseDependencyValuesSource(_ src: String) -> [String: String] {
//        var map: [String: String] = [:]
//        
//        // Typed properties
//        if let re = try? NSRegularExpression(
//            pattern: #"\bvar\s+([A-Za-z_][A-Za-z0-9_]*)\s*:\s*([A-Za-z_][A-Za-z0-9_?.<>]+)\s*\{"#
//        ) {
//            re.enumerateMatches(in: src, range: NSRange(src.startIndex..., in: src)) { m, _, _ in
//                guard
//                    let m,
//                    let name = Range(m.range(at: 1), in: src).map({ String(src[$0]) }),
//                    let type = Range(m.range(at: 2), in: src).map({ String(src[$0]) })
//                else { return }
//                map[name] = type
//            }
//        }
//        
//        // Getter/setter using self[TypeName.self]
//        if let re2 = try? NSRegularExpression(
//            pattern: #"\bvar\s+([A-Za-z_][A-Za-z0-9_]*)\s*\{[^}]*?self\[\s*([A-Za-z_][A-Za-z0-9_]*)\.self\s*\]"#,
//            options: [.dotMatchesLineSeparators]
//        ) {
//            re2.enumerateMatches(in: src, range: NSRange(src.startIndex..., in: src)) { m, _, _ in
//                guard
//                    let m,
//                    let name = Range(m.range(at: 1), in: src).map({ String(src[$0]) }),
//                    let type = Range(m.range(at: 2), in: src).map({ String(src[$0]) })
//                else { return }
//                if map[name] == nil { map[name] = type }
//            }
//        }
//        
//        return map
//    }
    
    /// Builds map of DependencyValues property -> backing type.
    /// 1) First tries from already parsed project symbols (your extensions).
    /// 2) If empty, tries to load from swift-dependencies checkout quickly.
//    func collectDependencyValueKeys(from symbols: [String: SymbolContent]) async -> [String: String] {
//        var map: [String: String] = [:]
//        
//        // 1) Project-local extensions (what you already had)
//        for (_, content) in symbols {
//            guard content.symbol.kind == .extensionWord,
//                  content.symbol.name == "DependencyValues" else { continue }
//            
//            let src = content.content
//            
//            // Typed: var foo: TypeName {
//            if let re = try? NSRegularExpression(
//                pattern: #"\bvar\s+([A-Za-z_][A-Za-z0-9_]*)\s*:\s*([A-Za-z_][A-Za-z0-9_?.<>]+)\s*\{"#
//            ) {
//                re.enumerateMatches(in: src, range: NSRange(src.startIndex..., in: src)) { m, _, _ in
//                    guard
//                        let m,
//                        let name = Range(m.range(at: 1), in: src).map({ String(src[$0]) }),
//                        let type = Range(m.range(at: 2), in: src).map({ String(src[$0]) })
//                    else { return }
//                    map[name] = type
//                }
//            }
//            
//            // Getter body: self[TypeName.self]
//            if let re2 = try? NSRegularExpression(
//                pattern: #"\bvar\s+([A-Za-z_][A-Za-z0-9_]*)\s*\{[^}]*?self\[\s*([A-Za-z_][A-Za-z0-9_]*)\.self\s*\]"#,
//                options: [.dotMatchesLineSeparators]
//            ) {
//                re2.enumerateMatches(in: src, range: NSRange(src.startIndex..., in: src)) { m, _, _ in
//                    guard
//                        let m,
//                        let name = Range(m.range(at: 1), in: src).map({ String(src[$0]) }),
//                        let type = Range(m.range(at: 2), in: src).map({ String(src[$0]) })
//                    else { return }
//                    if map[name] == nil { map[name] = type }
//                }
//            }
//        }
//        
//        if !map.isEmpty { return map }        // ✅ found in project
//        
//        // 2) Fast fallback to the single file from swift-dependencies
//        if let cached = cachedSwiftDependenciesKeys { return cached }
//        
//        if let fast = try? await loadSwiftDependenciesDependencyValuesFile(),
//           !fast.isEmpty {
//            cachedSwiftDependenciesKeys = fast
//            return fast
//        }
//        
//        return map // empty
//    }
    
    // Extracts keys like `errorToastCoordinator` from `@Dependency(\.errorToastCoordinator)`
//    private func extractDependencyKeys(in source: String) -> Set<String> {
//        // Matches: @Dependency(\.fooBar)
//        let pattern = #"@Dependency\s*\(\s*\\\.\s*([A-Za-z_][A-Za-z0-9_]*)\s*\)"#
//        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return [] }
//
//        var keys = Set<String>()
//        let range = NSRange(source.startIndex..., in: source)
//        regex.enumerateMatches(in: source, options: [], range: range) { match, _, _ in
//            guard
//                let match,
//                let r = Range(match.range(at: 1), in: source)
//            else { return }
//            keys.insert(String(source[r]))
//        }
//        return keys
//    }
    
    func scanProjectForDependencyKeys(files: [FileContent]) async -> [SymbolContent] {
        let allSymbols: [SymbolContent] = files.flatMap { parser.parse(file: $0) }
        let dependencyValueExtensions = allSymbols.filter {
            $0.symbol.kind == .extensionWord && $0.symbol.name == "DependencyValues"
        }
        return dependencyValueExtensions
    }

    /// Extract every `var <prop>: <Type> { ... }` and/or `self[<Type>.self]` from an
    /// `extension DependencyValues { ... }` source string.
    func getDependencySymbolsFromExtensionContent(_ content: String) -> [RegisteredDependencyValue] {
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

        // 2) Getter/setter body form: `var foo { get { self[TypeName.self] } ... }`
        //    (dotMatchesLineSeparators so it works across newlines)
//        if let body = try? NSRegularExpression(
//            pattern: #"\bvar\s+([A-Za-z_][A-Za-z0-9_]*)\s*\{[^}]*?self\[\s*([A-Za-z_][A-Za-z0-9_?.<>]+)\.self\s*\]"#,
//            options: [.dotMatchesLineSeparators]
//        ) {
//            let range = NSRange(content.startIndex..., in: content)
//            body.enumerateMatches(in: content, options: [], range: range) { m, _, _ in
//                guard
//                    let m,
//                    let nameR = Range(m.range(at: 1), in: content),
//                    let typeR = Range(m.range(at: 2), in: content)
//                else { return }
//                let varName = String(content[nameR])
//                let typeName = String(content[typeR])
//                // Don’t overwrite a typed match if it already exists
//                results.insert(.init(variableName: varName, symbolName: typeName))
//            }
//        }

        return Array(results)//.flatMap { $0 }
    }
}

struct RegisteredDependencyValue: Hashable {
    let variableName: String
    let symbolName: String
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
            
            let boundaryBefore = before.map { !isIdentChar($0) } ?? true
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
