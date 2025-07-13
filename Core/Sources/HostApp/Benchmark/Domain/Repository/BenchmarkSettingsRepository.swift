import Combine

protocol BenchmarkSettingsRepository {
    var benchmarkDirectories: AnyPublisher<[BenchmarkDirectory], Never> { get }
    var outputDirectory: AnyPublisher<String, Never> { get }
    func saveBenchmarkDirectory(_ directory: BenchmarkDirectory) throws
    func deleteBenchmarkDirectory(_ directory: BenchmarkDirectory) throws
    func saveBenchmarkOutputDirectory(_ directory: String) throws
    var projectRootURL: String { get }
}
