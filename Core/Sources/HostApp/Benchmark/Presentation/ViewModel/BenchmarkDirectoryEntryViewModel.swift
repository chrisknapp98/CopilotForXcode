import Combine
import Toast

class BenchmarkDirectoryEntryViewModel: ObservableObject {
    @Published private(set) var taskStates: [TaskStatus] = []
    
    private(set) var directory: BenchmarkDirectory
    private let benchmarkSettingsRepository: BenchmarkSettingsRepository
    private let benchmarkManager: BenchmarkManager
    private var cancellables = Set<AnyCancellable>()
    private var toast: ToastController { ToastControllerDependencyKey.liveValue }
    
    init(
        directory: BenchmarkDirectory,
        benchmarkSettingsRepository: BenchmarkSettingsRepository,
        benchmarkManager: BenchmarkManager
    ) {
        self.directory = directory
        self.benchmarkSettingsRepository = benchmarkSettingsRepository
        self.benchmarkManager = benchmarkManager
        benchmarkManager.taskStates
            .map { $0[directory] ?? [] }
            .assign(to: \.taskStates, on: self)
            .store(in: &cancellables)
    }
    
    func runBenchmark(for directory: BenchmarkDirectory) async throws {
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
    
    func runTask(index: Int, in directory: BenchmarkDirectory) async {
        await benchmarkManager.runTask(at: index, in: directory)
    }
}
