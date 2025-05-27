protocol BenchmarkModuleType {
    func provide() -> BenchmarkViewModel
    func provide() -> OutputConfigurationViewModel
    func provide() -> AddDirectoryViewModel
}

class BenchmarkModule: BenchmarkModuleType {
    private var benchmarkSettingsRepository: BenchmarkSettingsRepository?
    
    static let shared: BenchmarkModuleType = BenchmarkModule()
    
    private func component() -> LocalStorageManager {
        UserDefaultsLocalStorageManager()
    }
    
    private func component() -> BenchmarkSettingsRepository {
        if let repository = benchmarkSettingsRepository {
            return repository
        } else {
            let repository = LocalBenchmarkSettingsRepository(
                localStorageManager: component()
            )
            benchmarkSettingsRepository = repository
            return repository
        }
    }
    
    func provide() -> BenchmarkViewModel {
        BenchmarkViewModel(
            benchmarkSettingsRepository: component()
        )
    }
    
    func provide() -> OutputConfigurationViewModel {
        OutputConfigurationViewModel(
            benchmarkSettingsRepository: component()
        )
    }
    
    func provide() -> AddDirectoryViewModel {
        AddDirectoryViewModel(
            benchmarkSettingsRepository: component()
        )
    }
}
