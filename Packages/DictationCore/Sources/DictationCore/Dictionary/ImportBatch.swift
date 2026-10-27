import Foundation

public struct ImportBatch: Equatable, Sendable {
    public var entries: [DictionaryEntry]
    public var skipped: Int

    public init(entries: [DictionaryEntry], skipped: Int) {
        self.entries = entries
        self.skipped = skipped
    }
}
