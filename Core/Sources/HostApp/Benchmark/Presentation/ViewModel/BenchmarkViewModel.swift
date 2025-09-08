import Combine
import Toast

class BenchmarkViewModel: ObservableObject {
    @Published var benchmarkDirectories: [BenchmarkDirectory] = []
    @Published var isMultiFileContextEnabled: Bool = true {
        didSet {
            guard oldValue != isMultiFileContextEnabled else { return }
            Task { await benchmarkManager.updateMultiFileContextState(isMultiFileContextEnabled) }
        }
    }
    @Published private(set) var taskStates: [BenchmarkDirectory: [TaskStatus]] = [:]
    @Published var selectedLanguageModel: GenAILanguageModel = .defaultModel {
        didSet {
            guard oldValue != selectedLanguageModel else { return }
            Task { await benchmarkManager.changeGenAIModel(to: selectedLanguageModel) }
        }
    }
    
    private let benchmarkSettingsRepository: BenchmarkSettingsRepository
    private let benchmarkManager: BenchmarkManager
    private var cancellables = Set<AnyCancellable>()
    private var toast: ToastController { ToastControllerDependencyKey.liveValue }
    
    init(
        benchmarkSettingsRepository: BenchmarkSettingsRepository,
        benchmarkManager: BenchmarkManager
    ) {
        self.benchmarkSettingsRepository = benchmarkSettingsRepository
        self.benchmarkManager = benchmarkManager
        benchmarkManager.isMultiFileEnabled
            .assign(to: \.isMultiFileContextEnabled, on: self)
            .store(in: &cancellables)
        benchmarkManager.taskStates.assign(to: \.taskStates, on: self).store(in: &cancellables)
        benchmarkManager.selectedGenAIModel
            .assign(to: \.selectedLanguageModel, on: self)
            .store(in: &cancellables)
    }
    
    func loadBenchmarkDirectories() {
        benchmarkSettingsRepository.benchmarkDirectories
            .assign(to: \.benchmarkDirectories, on: self)
            .store(in: &cancellables)
    }
}
