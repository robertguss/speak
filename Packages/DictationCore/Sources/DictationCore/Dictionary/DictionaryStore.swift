import Foundation

public enum DictionaryStoreError: Error, Equatable {
    case duplicate
}

public struct MergeSummary: Equatable, Sendable {
    public var added: Int
    public var alreadyPresent: Int
}

public struct DictionaryStore: Sendable {
    let items: any ItemStore

    public init(items: any ItemStore) {
        self.items = items
    }

    public static func keychain(accessGroup: String = AppConstants.keychainAccessGroup) -> DictionaryStore {
        DictionaryStore(items: KeychainItemStore(accessGroup: accessGroup))
    }

    /// Every readable entry, highest hint priority first. Throws when the keychain can't be read.
    public func entries() throws -> [DictionaryEntry] {
        try Self.decode(items.readAll().values).sorted(by: DictionaryEntry.priority)
    }

    /// Adds a new entry; throws `.duplicate` when an entry already does the same job.
    public func add(_ entry: DictionaryEntry) throws {
        guard try !Self.decode(items.readAll().values).contains(where: { $0.matchKey == entry.matchKey }) else { throw DictionaryStoreError.duplicate }
        try write(entry, existing: nil)
    }

    /// Replaces the stored entry with the same ID; throws `.duplicate` when the edit collides with another entry.
    /// An edit that changes what the entry matches moves it to that match's item.
    public func update(_ entry: DictionaryEntry) throws {
        let stored = try items.readAll()
        let others = Self.decode(stored.filter { $0.key != entry.id }.values)
        guard !others.contains(where: { $0.matchKey == entry.matchKey }) else { throw DictionaryStoreError.duplicate }
        var moved = entry
        moved.id = DictionaryEntry.itemID(for: entry.matchKey)
        try write(moved, existing: stored[entry.id])
        if moved.id != entry.id { try items.delete(id: entry.id) }
    }

    public func delete(id: String) throws {
        try items.delete(id: id)
    }

    /// Adds every entry that doesn't match an existing one or an earlier one in the batch.
    public func merge(_ batch: [DictionaryEntry]) throws -> MergeSummary {
        var keys = Set(try Self.decode(items.readAll().values).map(\.matchKey))
        var summary = MergeSummary(added: 0, alreadyPresent: 0)
        for entry in batch {
            guard keys.insert(entry.matchKey).inserted else {
                summary.alreadyPresent += 1
                continue
            }
            try write(entry, existing: nil)
            summary.added += 1
        }
        return summary
    }

    /// Unreadable items are skipped.
    private static func decode(_ items: some Sequence<Data>) -> [DictionaryEntry] {
        let decoder = JSONDecoder()
        return items.compactMap { try? decoder.decode(DictionaryEntry.self, from: $0) }
    }

    private func write(_ entry: DictionaryEntry, existing: Data?) throws {
        var object = existing.flatMap { (try? JSONSerialization.jsonObject(with: $0)) as? [String: Any] } ?? [:]
        let fields = try JSONSerialization.jsonObject(with: JSONEncoder().encode(entry)) as? [String: Any] ?? [:]
        object.merge(fields) { _, new in new }
        if entry.heardAs == nil { object.removeValue(forKey: "heardAs") }
        try items.write(JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]), id: entry.id)
    }
}
