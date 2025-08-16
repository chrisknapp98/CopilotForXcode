public struct FileContent {
    let fileURL: String
    let content: String
    
    public init(fileURL: String, content: String) {
        self.fileURL = fileURL
        self.content = content
    }
}
