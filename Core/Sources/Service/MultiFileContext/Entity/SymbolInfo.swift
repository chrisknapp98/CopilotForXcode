public struct SymbolInfo {
    public let name: String
    public let kind: ClassificationKeywords
    public let startLine: Int
    public let endLine: Int
    public let content: String
    public internal(set) var extensions: [SymbolContent] = []
}
