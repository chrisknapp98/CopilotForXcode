import Foundation
import Workspace
import XcodeInspector
import SwiftSyntax
import SwiftParser

class MultiFileContextManager {
    private let workspaceProvider: WorkspaceProvider
    
//    private static let classificationKeywords: [String] = ["class", "struct", "enum", "actor", "protocol", "func", "var", "let"]
//    private static let classificationKeywordsWithSpecialCases: [String] = ["extension", "typealias"]
    
    init(workspaceProvider: WorkspaceProvider) {
        self.workspaceProvider = workspaceProvider
    }
    
    /// List files within workspace recursively
    /// Retrieved from: https://stackoverflow.com/a/57640445
    func listFilesInWorkspace() async -> [String] {
        guard let workspace: Workspace = try? await workspaceProvider.workspace()
        else { return [] }
        var files = [String]()
        if let enumerator = FileManager.default.enumerator(at: workspace.workspaceURL, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles, .skipsPackageDescendants]) {
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
    
    func classifyContentWithinFile() async -> [String: SymbolContent] {
        let fileContents = await readFileContents()
        var result: [String: SymbolContent] = [:]

        for file in fileContents {
            let sourceFile = Parser.parse(source: file.content)
            let converter = SourceLocationConverter(fileName: file.fileURL, tree: sourceFile)
            let collector = DeclarationCollector(sourceLocationConverter: converter, sourceText: file.content)
            collector.walk(sourceFile)
            var symbols: [SymbolContent] = collector.symbols.map { symbol in
                SymbolContent(fileURL: file.fileURL, content: file.content, symbol: symbol)
            }
            mergeExtensionsIntoBaseDeclarations(&symbols)
            for symbol in symbols {
                result[symbol.symbol.name] = symbol
            }
        }

        return result
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

struct FileContent {
    let fileURL: String
    let content: String
    
    var fileName: String {
        let fileNameWithExtension = String(fileURL.split(separator: "/").last ?? "")
        let fileName: String = fileNameWithExtension.replacingOccurrences(of: ".swift", with: "")
        return fileName
    }
}

struct SymbolContent {
    let fileURL: String
    let content: String
    var symbol: SymbolInfo
}

enum ClassificationKeywords: String {
    case classWord = "class"
    case structWord = "struct"
    case enumWord = "enum"
    case actorWord = "actor"
    case protocolWord = "protocol"
    case funcWord = "func"
    case varWord = "var"
    case letWord = "let"
    case extensionWord = "extension"
    case typealiasWord = "typealias"
}

struct SymbolInfo {
    let name: String
    let kind: ClassificationKeywords
    let startLine: Int
    let endLine: Int
    let content: String
    var extensions: [SymbolContent] = []
}

import SwiftSyntax
//import SwiftSyntaxParser

class DeclarationCollector: SyntaxVisitor {
    var symbols: [SymbolInfo] = []
    let sourceLocationConverter: SourceLocationConverter
    let sourceText: String

    init(sourceLocationConverter: SourceLocationConverter, sourceText: String) {
        self.sourceLocationConverter = sourceLocationConverter
        self.sourceText = sourceText
        super.init(viewMode: .all)
    }
    
//    override func visit(_ node: ImportDeclSyntax) -> SyntaxVisitorContinueKind {
//        recordSymbol(name: node.name.text, kind: "import", node: node)
//        return .skipChildren
//    }

    override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        recordSymbol(name: node.name.text, kind: ClassificationKeywords.classWord, node: node)
        return .skipChildren
    }

    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        recordSymbol(name: node.name.text, kind: ClassificationKeywords.structWord, node: node)
        return .skipChildren
    }

    override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
        recordSymbol(name: node.name.text, kind: ClassificationKeywords.enumWord, node: node)
        return .skipChildren
    }

    override func visit(_ node: ProtocolDeclSyntax) -> SyntaxVisitorContinueKind {
        recordSymbol(name: node.name.text, kind: ClassificationKeywords.protocolWord, node: node)
        return .skipChildren
    }
    
    override func visit(_ node: ActorDeclSyntax) -> SyntaxVisitorContinueKind {
        recordSymbol(name: node.name.text, kind: ClassificationKeywords.actorWord, node: node)
        return .skipChildren
    }

    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        recordSymbol(name: node.name.text, kind: ClassificationKeywords.funcWord, node: node)
        return .skipChildren
    }

    override func visit(_ node: VariableDeclSyntax) -> SyntaxVisitorContinueKind {
        guard let binding = node.bindings.first,
              let pattern = binding.pattern.as(IdentifierPatternSyntax.self),
              let keyword: ClassificationKeywords = ClassificationKeywords(rawValue: node.bindingSpecifier.text) else {
            return .skipChildren
        }
        recordSymbol(name: pattern.identifier.text, kind: keyword, node: node)
        return .skipChildren
    }

    override func visit(_ node: ExtensionDeclSyntax) -> SyntaxVisitorContinueKind {
        let name = node.extendedType.trimmedDescription
        recordSymbol(name: name, kind: ClassificationKeywords.extensionWord, node: node)
        return .skipChildren
    }
    
    override func visit(_ node: TypeAliasDeclSyntax) -> SyntaxVisitorContinueKind {
        recordSymbol(name: node.name.text, kind: ClassificationKeywords.typealiasWord, node: node)
        return .skipChildren
    }

    private func recordSymbol(name: String, kind: ClassificationKeywords, node: SyntaxProtocol) {
        let startLoc = sourceLocationConverter.location(for: node.positionAfterSkippingLeadingTrivia)
        let endLoc = sourceLocationConverter.location(for: node.endPositionBeforeTrailingTrivia)
        let startLineIndex = startLoc.line - 1
        let endLineIndex = endLoc.line - 1

        let lines = sourceText.split(separator: "\n", omittingEmptySubsequences: false)

        let contentLines = lines[startLineIndex...min(endLineIndex, lines.count - 1)]
        let content = contentLines.joined(separator: "\n")
        
        let symbol = SymbolInfo(
            name: name,
            kind: kind,
            startLine: startLoc.line,
            endLine: endLoc.line,
            content: content
        )
        symbols.append(symbol)
    }
}
