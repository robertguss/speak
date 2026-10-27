import Foundation

public struct DictionaryEntry: Codable, Equatable, Identifiable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case word
        case replacement
    }

    public var id: String
    public var kind: Kind
    public var text: String
    public var heardAs: String?
    public var starred: Bool
    public var useCount: Int
    public var addedAt: Date

    public init(
        id: String = UUID().uuidString,
        kind: Kind,
        text: String,
        heardAs: String? = nil,
        starred: Bool = false,
        useCount: Int = 0,
        addedAt: Date = Date()
    ) {
        self.id = id
        self.kind = kind
        self.text = text
        self.heardAs = kind == .replacement ? heardAs : nil
        self.starred = starred
        self.useCount = useCount
        self.addedAt = addedAt
    }

    public static func word(_ text: String) -> DictionaryEntry {
        DictionaryEntry(kind: .word, text: text)
    }

    public static func replacement(_ heardAs: String, with text: String) -> DictionaryEntry {
        DictionaryEntry(kind: .replacement, text: text, heardAs: heardAs)
    }

    /// Lenient like `AppPreferences`: only `id`, `kind`, and `text` are required.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        kind = try c.decode(Kind.self, forKey: .kind)
        text = try c.decode(String.self, forKey: .text)
        heardAs = kind == .replacement ? (try? c.decodeIfPresent(String.self, forKey: .heardAs)) ?? nil : nil
        starred = (try? c.decodeIfPresent(Bool.self, forKey: .starred)) ?? false
        useCount = (try? c.decodeIfPresent(Int.self, forKey: .useCount)) ?? 0
        addedAt = (try? c.decodeIfPresent(Date.self, forKey: .addedAt)) ?? .distantPast
    }

    var matchKey: String {
        switch kind {
        case .word: "word:" + text.lowercased()
        case .replacement: "replacement:" + (heardAs ?? "").lowercased()
        }
    }

    static func priority(_ a: DictionaryEntry, _ b: DictionaryEntry) -> Bool {
        if a.starred != b.starred { return a.starred }
        if a.useCount != b.useCount { return a.useCount > b.useCount }
        if a.addedAt != b.addedAt { return a.addedAt > b.addedAt }
        return a.text.localizedCaseInsensitiveCompare(b.text) == .orderedAscending
    }
}
