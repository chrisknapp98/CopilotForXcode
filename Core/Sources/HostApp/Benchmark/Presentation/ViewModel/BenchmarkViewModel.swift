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
    @Published private(set) var taskStates: [TaskStatus] = []
    
    private let benchmarkSettingsRepository: BenchmarkSettingsRepository
    private let benchmarkManager: RealtimeSuggestionControllerBenchmarkManager
    private var cancellables = Set<AnyCancellable>()
    private var toast: ToastController { ToastControllerDependencyKey.liveValue }
    
    init(benchmarkSettingsRepository: BenchmarkSettingsRepository) {
        self.benchmarkSettingsRepository = benchmarkSettingsRepository
        self.benchmarkManager = RealtimeSuggestionControllerBenchmarkManager(benchmarkSettingsRepository: benchmarkSettingsRepository)
        benchmarkManager.isMultiFileEnabled
            .assign(to: \.isMultiFileContextEnabled, on: self)
            .store(in: &cancellables)
        benchmarkManager.taskStates.assign(to: \.taskStates, on: self).store(in: &cancellables)
    }
    
    func loadBenchmarkDirectories() {
        benchmarkSettingsRepository.benchmarkDirectories
            .assign(to: \.benchmarkDirectories, on: self)
            .store(in: &cancellables)
    }
    
    func runBenchmark(for directory: BenchmarkDirectory) async throws {
        // TODO: Implement the logic to run the benchmark for the given directory
        print("Running benchmark for \(directory.url.path)")
        try await benchmarkManager.getCodeSuggestions(at: directory)
    }
    
    
    func deleteDirectory(_ directory: BenchmarkDirectory) {
        do {
            try benchmarkSettingsRepository.deleteBenchmarkDirectory(directory)
            toast.toast(content: "Directory deleted successfully.", level: .info)
        } catch {
            toast.toast(content: "Failed deleting directory.", level: .error)
        }
    }
}
