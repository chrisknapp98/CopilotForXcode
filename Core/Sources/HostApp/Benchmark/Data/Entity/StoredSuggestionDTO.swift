struct StoredSuggestionDTO: Codable {
    let fileURL: String
    let id: String
    let suggestionText: String
    let position: CursorPositionDTO
    let range: CursorRangeDTO
    let createdAt: String
    let relevantSymbols: [RelevantSymbolsDTO]
    let model: String
    
    struct CursorPositionDTO: Codable {
        let line: Int
        let character: Int
    }
    
    struct CursorRangeDTO: Codable {
        let start: CursorPositionDTO
        let end: CursorPositionDTO
    }
    
    struct RelevantSymbolsDTO: Codable {
        let fileURL: String
        let name: String
        let content: String
        let startLine: Int
        let endLine: Int
        let kind: String
    }
}
