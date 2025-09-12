import Foundation

struct SuggestionRequest {
    
    struct CursorPosition {
        var line: Int
        var character: Int
    }

    struct RelevantCodeSnippet {
        var path: String
        var language: String?
        var code: String
    }
    
    var fileURL: URL
    var relativePath: String
    var content: String
    var originalContent: String
    var lines: [String]
    var cursorPosition: CursorPosition
    var cursorOffset: Int
    var tabSize: Int
    var indentSize: Int
    var usesTabsForIndentation: Bool
    var relevantCodeSnippets: [RelevantCodeSnippet]
}
