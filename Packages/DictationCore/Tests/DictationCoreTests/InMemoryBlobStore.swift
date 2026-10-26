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

extension SettingsStore {
    static func inMemory(preferencesJSON: String? = nil) -> (SettingsStore, preferences: InMemoryBlobStore, secrets: InMemoryBlobStore) {
        let preferences = InMemoryBlobStore(json: preferencesJSON)
        let secrets = InMemoryBlobStore()
        return (SettingsStore(preferences: preferences, secrets: SecretStore(blob: secrets)), preferences, secrets)
    }
}
