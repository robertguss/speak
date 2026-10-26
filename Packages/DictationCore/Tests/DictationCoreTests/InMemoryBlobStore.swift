import Foundation
@testable import DictationCore

/// Stands in for one keychain item in tests.
final class InMemoryBlobStore: BlobStore, @unchecked Sendable {
    private let lock = NSLock()
    private var data: Data?
    private(set) var writeCount = 0

    init(json: String? = nil) {
        data = json.map { Data($0.utf8) }
    }

    func read() throws -> Data? {
        lock.withLock { data }
    }

    func write(_ data: Data) throws {
        lock.withLock {
            self.data = data
            writeCount += 1
        }
    }

    var jsonObject: [String: Any] {
        lock.withLock { data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:] }
    }
}

/// Stands in for a set of keychain items in tests.
final class InMemoryItemStore: ItemStore, @unchecked Sendable {
    private let lock = NSLock()
    private var items: [String: Data]

    init(items: [String: Data] = [:]) {
        self.items = items
    }

    var snapshot: [String: Data] { lock.withLock { items } }

    func readAll() throws -> [String: Data] { snapshot }
    func write(_ data: Data, id: String) throws { lock.withLock { items[id] = data } }
    func delete(id: String) throws { lock.withLock { _ = items.removeValue(forKey: id) } }
}

extension SettingsStore {
    static func inMemory(preferencesJSON: String? = nil) -> (SettingsStore, preferences: InMemoryBlobStore, secrets: InMemoryBlobStore) {
        let preferences = InMemoryBlobStore(json: preferencesJSON)
        let secrets = InMemoryBlobStore()
        let store = SettingsStore(preferences: preferences, secrets: SecretStore(blob: secrets), dictionary: DictionaryStore(items: InMemoryItemStore()))
        return (store, preferences, secrets)
    }
}
