import Foundation
import SuggestionBasic
import Service

struct SuggestionResponse {
    let suggestion: SuggestionBasic.CodeSuggestion
    let fileURL: URL
    let relevantSymbolsFromRequest: [SymbolContent]
    let model: GenAILanguageModel
}
