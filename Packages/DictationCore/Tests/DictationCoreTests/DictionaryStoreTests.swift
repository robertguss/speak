import Synchronization
import XCTest
@testable import DictationCore

final class DictionaryStoreTests: XCTestCase {
    func testEntriesAddedOnTwoOutOfSyncDevicesBothSurviveSync() throws {
        let start = InMemoryItemStore()
        try DictionaryStore(items: start).add(.word("Kubernetes"))

        // Each device starts from the same synced items and edits offline.
        let mac = InMemoryItemStore(items: start.snapshot)
        let phone = InMemoryItemStore(items: start.snapshot)
        try DictionaryStore(items: mac).add(.word("Populi"))
        try DictionaryStore(items: phone).add(.word("kubectl"))

        // iCloud Keychain syncs per item: every item either device wrote ends up on both.
        let synced = InMemoryItemStore(items: mac.snapshot.merging(phone.snapshot) { a, _ in a })
        XCTAssertEqual(Set(try DictionaryStore(items: synced).entries().map(\.text)), ["Kubernetes", "Populi", "kubectl"])
    }

    func testDeleteRemovesOnlyThatEntryAndEditsKeepUnknownFields() throws {
        let items = InMemoryItemStore()
        let store = DictionaryStore(items: items)
        let keep = DictionaryEntry.word("Kubernetes")
        let gone = DictionaryEntry.word("Populi")
        try store.add(keep)
        try store.add(gone)

        // A newer build wrote a field this build doesn't know.
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(items.snapshot[keep.id])) as? [String: Any])
        object["pronunciation"] = "koo-ber-net-eez"
        try items.write(JSONSerialization.data(withJSONObject: object), id: keep.id)

        try store.delete(id: gone.id)
        var edited = keep
        edited.starred = true
        try store.update(edited)

        XCTAssertEqual(try store.entries().map(\.text), ["Kubernetes"])
        XCTAssertEqual(try store.entries().first?.starred, true)
        let stored = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(items.snapshot[keep.id])) as? [String: Any])
        XCTAssertEqual(stored["pronunciation"] as? String, "koo-ber-net-eez")
    }

    func testMergeSkipsWordsAlreadyPresentIgnoringCase() throws {
        let store = DictionaryStore(items: InMemoryItemStore())
        try store.add(.word("KUBERNETES"))

        let summary = try store.merge([.word("Kubernetes"), .word("kubernetes"), .word("PR")])

        XCTAssertEqual(summary, MergeSummary(added: 1, alreadyPresent: 2))
        XCTAssertEqual(Set(try store.entries().map(\.text)), ["KUBERNETES", "PR"])
    }

    func testReplacementsMatchOnWhatIsHeardNotTheOutput() throws {
        let store = DictionaryStore(items: InMemoryItemStore())

        XCTAssertEqual(try store.merge([.replacement("pee are", with: "PR"), .replacement("P R", with: "PR")]), MergeSummary(added: 2, alreadyPresent: 0))
        XCTAssertEqual(try store.merge([.replacement("Pee Are", with: "PR")]), MergeSummary(added: 0, alreadyPresent: 1))
    }

    func testWordAndReplacementWithSameTextAreNotDuplicates() throws {
        let store = DictionaryStore(items: InMemoryItemStore())
        try store.add(.word("PR"))
        try store.add(.replacement("pee are", with: "PR"))
        XCTAssertEqual(try store.entries().count, 2)
    }

    func testAddingOrEditingIntoADuplicateIsRejected() throws {
        let store = DictionaryStore(items: InMemoryItemStore())
        try store.add(.word("Kubernetes"))
        var other = DictionaryEntry.word("Populi")
        try store.add(other)

        XCTAssertThrowsError(try store.add(.word("kubernetes"))) { XCTAssertEqual($0 as? DictionaryStoreError, .duplicate) }
        other.text = "KUBERNETES"
        XCTAssertThrowsError(try store.update(other)) { XCTAssertEqual($0 as? DictionaryStoreError, .duplicate) }
        XCTAssertEqual(Set(try store.entries().map(\.text)), ["Kubernetes", "Populi"])
    }

    func testEntriesAreOrderedStarredThenMostUsedThenNewest() throws {
        let store = DictionaryStore(items: InMemoryItemStore())
        let now = Date()
        _ = try store.merge([
            DictionaryEntry(kind: .word, text: "newest", addedAt: now),
            DictionaryEntry(kind: .word, text: "used", useCount: 50, addedAt: now - 100),
            DictionaryEntry(kind: .word, text: "starred", starred: true, addedAt: now - 200),
            DictionaryEntry(kind: .word, text: "oldest", addedAt: now - 300),
        ])
        XCTAssertEqual(try store.entries().map(\.text), ["starred", "used", "newest", "oldest"])
    }

    func testUnreadableKeychainMakesEditsThrowWithoutWriting() throws {
        let items = UnreadableItems()
        let store = DictionaryStore(items: items)
        XCTAssertThrowsError(try store.add(.word("Kubernetes")))
        XCTAssertThrowsError(try store.merge([.word("Kubernetes")]))
        XCTAssertEqual(items.writes.withLock { $0 }, 0)
    }
}

private final class UnreadableItems: ItemStore {
    let writes = Mutex(0)
    func readAll() throws -> [String: Data] { throw KeychainError(status: errSecInteractionNotAllowed) }
    func write(_ data: Data, id: String) throws { writes.withLock { $0 += 1 } }
    func delete(id: String) throws {}
}
