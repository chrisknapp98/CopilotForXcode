import Combine
import Toast

class ConfigurationViewModel: ObservableObject {
    @Published var outputDirectory: String = ""
    @Published var openAIKey: String = ""
    private var cancellables = Set<AnyCancellable>()
    private var toast: ToastController { ToastControllerDependencyKey.liveValue }
    
    private let benchmarkSettingsRepository: BenchmarkSettingsRepository
    
    init(benchmarkSettingsRepository: BenchmarkSettingsRepository) {
        self.benchmarkSettingsRepository = benchmarkSettingsRepository
        benchmarkSettingsRepository.outputDirectory
            .assign(to: \.outputDirectory, on: self)
            .store(in: &cancellables)
        benchmarkSettingsRepository.openAIKey
            .assign(to: \.openAIKey, on: self)
            .store(in: &cancellables)
    }
    
    func saveOutputDirectory(_ directory: String) {
        do {
            try benchmarkSettingsRepository.saveBenchmarkOutputDirectory(directory)
            toast.toast(content: "Output Directory changed.", level: .info)
        } catch {
            toast.toast(content: "Failed changing output directory.", level: .error)
        }
    }
    
    func saveOpenAIKey(_ key: String) {
        do {
            try benchmarkSettingsRepository.saveOpenAIKey(key)
            toast.toast(content: "OpenAI Key changed.", level: .info)
        } catch {
            toast.toast(content: "Failed changing OpenAI Key.", level: .error)
        }
    }
}

