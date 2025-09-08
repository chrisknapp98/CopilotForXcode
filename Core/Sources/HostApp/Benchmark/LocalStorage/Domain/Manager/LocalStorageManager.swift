protocol LocalStorageManager {
    func save<T: Codable>(codable: T, key: String) throws
    func load<T: Codable>(key: String) throws -> T
    func delete(key: String)
}
