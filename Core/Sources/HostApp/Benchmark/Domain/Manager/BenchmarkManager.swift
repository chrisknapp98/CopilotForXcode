import Combine

protocol BenchmarkManager {
    var isMultiFileEnabled: AnyPublisher<Bool, Never> { get }
    var taskStates: AnyPublisher<[BenchmarkDirectory: [TaskStatus]], Never> { get }
    var selectedGenAIModel: AnyPublisher<GenAILanguageModel, Never> { get }
    func getCodeSuggestions(at benchmarkDirectory: BenchmarkDirectory) async throws
    func runTask(at index: Int, in benchmarkDirectory: BenchmarkDirectory) async
    @MainActor
    func changeGenAIModel(to newModel: GenAILanguageModel)
    @MainActor
    func updateMultiFileContextState(_ newValue: Bool)
}
