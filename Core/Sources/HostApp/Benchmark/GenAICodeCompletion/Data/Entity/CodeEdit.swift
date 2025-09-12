struct CodeEdit: Codable {
    struct Position: Codable {
        let line: Int
        let character: Int
    }
    struct TextRange: Codable {
        let start: Position
        let end: Position
    }
    
    /// Replacement text that MUST include the full (updated) content of the cursor's line.
    let text: String
    let range: TextRange
}
