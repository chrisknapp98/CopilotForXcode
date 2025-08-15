import Foundation
import Combine

class LocalBenchmarkSettingsRepository: BenchmarkSettingsRepository {
    private let localStorageManager: LocalStorageManager
    private let benchmarkDirectoriesKey = "benchmarkDirectories"
    private let benchmarkOutputDirectoryKey = "benchmarkOutputDirectory"
    private let openAIKeyDefaultsKey = "openAIKey"
    
    private var defaultOutputDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Desktop/benchmark_output")
    }

    private let currentBenchmarkDirectories: CurrentValueSubject<[BenchmarkDirectory], Never> = CurrentValueSubject([])
    var benchmarkDirectories: AnyPublisher<[BenchmarkDirectory], Never> {
        currentBenchmarkDirectories.eraseToAnyPublisher()
    }
    
    private let benchmarkOutputDirectory: CurrentValueSubject<String, Never> = CurrentValueSubject("")
    var outputDirectory: AnyPublisher<String, Never> {
        benchmarkOutputDirectory.eraseToAnyPublisher()
    }
    
    private let currentOpenAIKey: CurrentValueSubject<String, Never> = CurrentValueSubject("")
    var openAIKey: AnyPublisher<String, Never> {
        currentOpenAIKey.eraseToAnyPublisher()
    }
    
    init(localStorageManager: LocalStorageManager) {
        self.localStorageManager = localStorageManager
        if let benchmarkDirectories = try? retrieveBenchmarkDirectories() {
            currentBenchmarkDirectories.send(benchmarkDirectories)
        }
        if let outputDirectory = try? loadBenchmarkOutputDirectory() {
            benchmarkOutputDirectory.send(outputDirectory)
        }
        if let openAIKey = try? loadOpenAIKey() {
            currentOpenAIKey.send(openAIKey)
        }
    }
    
    func saveBenchmarkDirectory(_ directory: BenchmarkDirectory) throws {
        let currentEntries = currentBenchmarkDirectories.value
        let updatedEntries = currentEntries + [directory]
        let data = updatedEntries.mapToDTOs()
        try localStorageManager.save(codable: data, key: benchmarkDirectoriesKey)
        currentBenchmarkDirectories.send(updatedEntries)
    }
    
    func deleteBenchmarkDirectory(_ directory: BenchmarkDirectory) throws {
        var currentEntries = currentBenchmarkDirectories.value
        currentEntries.removeAll { $0 == directory }
        let data = currentEntries.mapToDTOs()
        try localStorageManager.save(codable: data, key: benchmarkDirectoriesKey)
        currentBenchmarkDirectories.send(currentEntries)
    }
    
    private func retrieveBenchmarkDirectories() throws -> [BenchmarkDirectory] {
        let data: [BenchmarkDirectoryDTO] = try localStorageManager.load(key: benchmarkDirectoriesKey)
        return data.map { $0.mapToDomain() }
    }
    
    func saveBenchmarkOutputDirectory(_ directory: String) throws {
        try localStorageManager.save(codable: directory, key: benchmarkOutputDirectoryKey)
        benchmarkOutputDirectory.send(directory)
    }
    
    private func loadBenchmarkOutputDirectory() throws -> String {
        do {
            return try localStorageManager.load(key: benchmarkOutputDirectoryKey)
        } catch LocalStorageError.noDataForKey {
            let defaultPath = defaultOutputDirectory.path
            try saveBenchmarkOutputDirectory(defaultPath)
            return defaultPath
        }
    }
    
    private func deleteBenchmarkOutputDirectory() {
    }
    
    private func loadOpenAIKey() throws -> String? {
        return try? localStorageManager.load(key: openAIKeyDefaultsKey)
    }
    
    func saveOpenAIKey(_ key: String) throws {
        try localStorageManager.save(codable: key, key: openAIKeyDefaultsKey)
        currentOpenAIKey.send(key)
    }
}

extension Array where Element == BenchmarkDirectory {
    func mapToDTOs() -> [BenchmarkDirectoryDTO] {
        return self.map { $0.mapToDTO() }
    }
}

extension BenchmarkDirectory {
    func mapToDTO() -> BenchmarkDirectoryDTO {
        return BenchmarkDirectoryDTO(name: name, url: url)
    }
}
   
extension BenchmarkDirectoryDTO {
    func mapToDomain() -> BenchmarkDirectory {
        return BenchmarkDirectory(name: name, url: url)
    }
}
