import SwiftSyntax

class SwiftDeclarationCollector: SyntaxVisitor {
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
