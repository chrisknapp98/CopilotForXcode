import Foundation

class UserDefaultsLocalStorageManager: LocalStorageManager {
    
    private let userDefaults: UserDefaults = UserDefaults()
    
    func save<T: Codable>(codable: T, key: String) throws {
        let encoder = JSONEncoder()
        guard let encoded = try? encoder.encode(codable) else {
            throw LocalStorageError.encodingError
        }
        userDefaults.set(encoded, forKey: key)
    }
    
    func load<T: Codable>(key: String) throws -> T {
        guard let data = userDefaults.data(forKey: key) else {
            throw LocalStorageError.noDataForKey
        }
        let decoder = JSONDecoder()
        guard let decoded = try? decoder.decode(T.self, from: data) else {
            throw LocalStorageError.decodingError
        }
        return decoded
    }
    
    func delete(key: String) {
        userDefaults.removeObject(forKey: key)
    }
    
}
