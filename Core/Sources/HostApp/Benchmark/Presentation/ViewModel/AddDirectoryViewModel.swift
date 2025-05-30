import Foundation
import Toast

class AddDirectoryViewModel: ObservableObject {
    private let benchmarkSettingsRepository: BenchmarkSettingsRepository
    private var toast: ToastController { ToastControllerDependencyKey.liveValue }
    
    init(benchmarkSettingsRepository: BenchmarkSettingsRepository) {
        self.benchmarkSettingsRepository = benchmarkSettingsRepository
    }
    
    func saveNewDirectory(name: String, directory: String) {
        do {
            try benchmarkSettingsRepository.saveBenchmarkDirectory(
                BenchmarkDirectory(
                    name: name,
                    url: URL(fileURLWithPath: directory)
                )
            )
            toast.toast(content: "Directory added successfully.", level: .info)
        } catch {
            toast.toast(content: "Failed adding directory.", level: .error)
        }
    }
}
