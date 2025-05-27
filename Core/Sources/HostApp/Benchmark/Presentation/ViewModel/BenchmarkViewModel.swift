import Combine
import Toast

class BenchmarkViewModel: ObservableObject {
    @Published var benchmarkDirectories: [BenchmarkDirectory] = []
    
    private let benchmarkSettingsRepository: BenchmarkSettingsRepository
    private var cancellables = Set<AnyCancellable>()
    private var toast: ToastController { ToastControllerDependencyKey.liveValue }
    
    init(benchmarkSettingsRepository: BenchmarkSettingsRepository) {
        self.benchmarkSettingsRepository = benchmarkSettingsRepository
    }
    
    func loadBenchmarkDirectories() {
        benchmarkSettingsRepository.benchmarkDirectories
            .assign(to: \.benchmarkDirectories, on: self)
            .store(in: &cancellables)
    }
    
    func runBenchmark(for directory: BenchmarkDirectory) {
        // TODO: Implement the logic to run the benchmark for the given directory
        print("Running benchmark for \(directory.url.path)")
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
