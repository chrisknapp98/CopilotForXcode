struct SymbolInfo {
    let name: String
    let kind: ClassificationKeywords
    let startLine: Int
    let endLine: Int
    let content: String
    var extensions: [SymbolContent] = []
}
