import SwiftSyntax
import SwiftParser

public protocol ProgrammingLanguageSyntaxParser {
    func parse(file: FileContent) -> [SymbolContent]
}

public class SwiftProgrammingLanguageSyntaxParser: ProgrammingLanguageSyntaxParser {
    
    public init() { }
    
    public func parse(file: FileContent) -> [SymbolContent] {
        let sourceFile = Parser.parse(source: file.content)
        let converter = SourceLocationConverter(fileName: file.fileURL, tree: sourceFile)
        let collector = SwiftDeclarationCollector(sourceLocationConverter: converter, sourceText: file.content)
        collector.walk(sourceFile)
        return collector.symbols.map { symbol in
            SymbolContent(fileURL: file.fileURL, content: file.content, symbol: symbol)
        }
    }
}
