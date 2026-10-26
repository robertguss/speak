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
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.robertguss.dictation",
            kSecAttrAccount as String: account,
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
        return (try? JSONDecoder().decode([String: String].self, from: data)) ?? [:]
    }
}
