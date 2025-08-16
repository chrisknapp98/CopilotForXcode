protocol BenchmarkModuleType {
    func provide() -> BenchmarkViewModel
    func provide(directory: BenchmarkDirectory) -> BenchmarkDirectoryEntryViewModel
    func provide() -> ConfigurationViewModel
    func provide() -> AddDirectoryViewModel
}

class BenchmarkModule: BenchmarkModuleType {
    private var benchmarkSettingsRepository: BenchmarkSettingsRepository?
    private var benchmarkManager: BenchmarkManager?
    
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
    
    private func component() -> BenchmarkManager {
        if let manager = benchmarkManager {
            return manager
        } else {
            let manager = MultiFileContextBenchmarkManager(
                benchmarkSettingsRepository: component()
            )
            benchmarkManager = manager
            return manager
        }
    }
    
    func provide() -> BenchmarkViewModel {
        BenchmarkViewModel(
            benchmarkSettingsRepository: component(),
            benchmarkManager: component()
        )
    }
    
    func provide(directory: BenchmarkDirectory) -> BenchmarkDirectoryEntryViewModel {
        BenchmarkDirectoryEntryViewModel(
            directory: directory,
            benchmarkSettingsRepository: component(),
            benchmarkManager: component()
        )
    }
    
    func provide() -> ConfigurationViewModel {
        ConfigurationViewModel(
            benchmarkSettingsRepository: component()
        )
    }
    
    func provide() -> AddDirectoryViewModel {
        AddDirectoryViewModel(
            benchmarkSettingsRepository: component()
        )
    }
}
