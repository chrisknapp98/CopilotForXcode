struct MetadataDTO: Codable {
    let taskId: Int
    let entrypoint: EntrypointDTO
    let files: [String]

    private enum CodingKeys: String, CodingKey {
        case taskId = "task_id"
        case entrypoint
        case files
    }
    
    struct EntrypointDTO: Codable {
        let filename: String
        let cursor: CursorPositionDTO
    }
    
    struct CursorPositionDTO: Codable {
        let line: Int
        let character: Int
    }
}
