import Foundation

struct StoredSuggestionDTO: Codable {
    let fileURL: String
    let id: String
    let suggestionText: String
    let position: CursorPositionDTO
    let range: CursorRangeDTO
    let createdAt: String
    let relevantSymbols: [RelevantSymbolsDTO]
    let model: String
    let relevantFileScanningDurationInSeconds: Double?
    
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
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(fileURL, forKey: .fileURL)
        try container.encode(id, forKey: .id)
        try container.encode(suggestionText, forKey: .suggestionText)
        try container.encode(position, forKey: .position)
        try container.encode(range, forKey: .range)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(relevantSymbols, forKey: .relevantSymbols)
        try container.encode(model, forKey: .model)

        if let value = relevantFileScanningDurationInSeconds {
            let rounded = Double(round(100 * value) / 100)
            try container.encode(rounded, forKey: .relevantFileScanningDurationInSeconds)
        }
    }
}
