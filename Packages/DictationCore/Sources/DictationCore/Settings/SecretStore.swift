import Foundation
import Security

/// One opaque blob of data, stored as a whole. The keychain backs it in the apps;
/// tests use an in-memory fake.
public protocol BlobStore: Sendable {
    func read() throws -> Data?
    func write(_ data: Data) throws
}

public struct KeychainError: Error, Equatable {
    public let status: OSStatus
}

/// A synchronizable generic-password item in the shared access group (KTD7).
public struct KeychainBlobStore: BlobStore {
    public let account: String
    public let accessGroup: String

    public init(account: String, accessGroup: String) {
        self.account = account
        self.accessGroup = accessGroup
    }

    private var baseQuery: [String: Any] {
        var query = Self.sharedAttributes(accessGroup: accessGroup)
        query[kSecAttrAccount as String] = account
        return query
    }

    static func sharedAttributes(accessGroup: String) -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.robertguss.speak",
            kSecAttrSynchronizable as String: true,
            kSecUseDataProtectionKeychain as String: true,
        ]
        if !accessGroup.isEmpty {
            query[kSecAttrAccessGroup as String] = accessGroup
        }
        return query
    }

    public func read() throws -> Data? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw KeychainError(status: status) }
        return result as? Data
    }

    public func write(_ data: Data) throws {
        let update = [kSecValueData as String: data]
        let status = SecItemUpdate(baseQuery as CFDictionary, update as CFDictionary)
        if status == errSecItemNotFound {
            var add = baseQuery
            add[kSecValueData as String] = data
            add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            let addStatus = SecItemAdd(add as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw KeychainError(status: addStatus) }
        } else if status != errSecSuccess {
            throw KeychainError(status: status)
        }
    }

    public func delete() throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw KeychainError(status: status) }
    }
}

public protocol ItemStore: Sendable {
    func readAll() throws -> [String: Data]
    func write(_ data: Data, id: String) throws
    func delete(id: String) throws
}

/// iCloud Keychain resolves conflicts per item, so entries added on different devices never overwrite each other.
public struct KeychainItemStore: ItemStore {
    static let prefix = "dictionary:"
    public let accessGroup: String

    public init(accessGroup: String) {
        self.accessGroup = accessGroup
    }

    public func readAll() throws -> [String: Data] {
        var query = KeychainBlobStore.sharedAttributes(accessGroup: accessGroup)
        query[kSecReturnAttributes as String] = true
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitAll
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return [:] }
        guard status == errSecSuccess else { throw KeychainError(status: status) }
        var items: [String: Data] = [:]
        for item in result as? [[String: Any]] ?? [] {
            guard let account = item[kSecAttrAccount as String] as? String, account.hasPrefix(Self.prefix),
                  let data = item[kSecValueData as String] as? Data else { continue }
            items[String(account.dropFirst(Self.prefix.count))] = data
        }
        return items
    }

    public func write(_ data: Data, id: String) throws {
        try blob(id).write(data)
    }

    public func delete(id: String) throws {
        try blob(id).delete()
    }

    private func blob(_ id: String) -> KeychainBlobStore {
        KeychainBlobStore(account: Self.prefix + id, accessGroup: accessGroup)
    }
}

/// API keys, stored as one dictionary keyed by `<role>:<host>` (KTD7).
/// Writes re-read the item and change only one entry, so keys entered on another device survive.
public struct SecretStore: Sendable {
    let blob: any BlobStore

    public init(blob: any BlobStore) {
        self.blob = blob
    }

    public static func name(for role: KeyRole, baseURL: URL) -> String {
        "\(role.rawValue):\(baseURL.host() ?? "")"
    }

    public func value(for name: String) -> String? {
        (try? all())?[name]
    }

    /// Stores `value` under `name`; `nil` or an empty string removes the entry.
    /// Throws without writing if the current item cannot be read, so other keys are never lost.
    public func setValue(_ value: String?, for name: String) throws {
        var entries = try all()
        if let value, !value.isEmpty {
            entries[name] = value
        } else {
            entries.removeValue(forKey: name)
        }
        try blob.write(JSONEncoder().encode(entries))
    }

    private func all() throws -> [String: String] {
        guard let data = try blob.read() else { return [:] }
        return try JSONDecoder().decode([String: String].self, from: data)
    }
}
