enum GenAILanguageModel: Hashable, CaseIterable, Identifiable {
    case githubCopilot
    case openAI(OpenAIModel)

    static var allCases: [GenAILanguageModel] {
        [.githubCopilot] + OpenAIModel.allCases.map { .openAI($0) }
    }

    var id: String {
        switch self {
        case .githubCopilot: return "githubCopilot"
        case .openAI(let m): return "openAI:\(m.rawValue)"
        }
    }

    var name: String {
        switch self {
        case .githubCopilot: return "GitHub Copilot"
        case .openAI(let m): return m.displayName
        }
    }

    static let defaultModel: GenAILanguageModel = .githubCopilot
}

enum OpenAIModel: String, CaseIterable, Hashable {
    case gpt4oMini = "gpt-4o-mini"
    case gpt4o     = "gpt-4o"
    case gpt5      = "gpt-5"

    var displayName: String {
        switch self {
        case .gpt4oMini: return "GPT-4o mini"
        case .gpt4o:     return "GPT-4o"
        case .gpt5:      return "GPT-5"
        }
    }
}
