enum ContextLevelLimit: CaseIterable {
    case firstLevel
    case secondLevel
    case thirdLevel
    
    var name: String {
        switch self {
        case .firstLevel: return "First Level"
        case .secondLevel: return "Second Level"
        case .thirdLevel: return "Third Level"
        }
    }
    
    var indexLimit: Int? {
        switch self {
        case .firstLevel: return 0
        case .secondLevel: return 1
        case .thirdLevel: return 2
        }
    }
}
