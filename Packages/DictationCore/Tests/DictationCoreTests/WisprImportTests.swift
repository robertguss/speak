import SQLite3
import XCTest
@testable import DictationCore

final class WisprCSVTests: XCTestCase {
    private func summary(_ entries: [DictionaryEntry]) -> [String] {
        entries.map { entry in entry.heardAs.map { "\($0) → \(entry.text)" } ?? entry.text }
    }

    func testOneColumnIsAWordAndTwoColumnsAreAReplacement() {
        let batch = WisprCSVParser.parse("Kubernetes\n\"Whisper Flow\",\"Wispr Flow\"\npee are,PR,\n")
        XCTAssertEqual(summary(batch.entries), ["Kubernetes", "Whisper Flow → Wispr Flow", "pee are → PR"])
        XCTAssertEqual(batch.entries.map(\.kind), [.word, .replacement, .replacement])
        XCTAssertEqual(batch.skipped, 0)
    }

    func testMalformedRowsAreSkippedAndCounted() {
        let batch = WisprCSVParser.parse("a,b,c\n\n\"unterminated\n\"say \"\"hi\"\"\"\n")
        XCTAssertEqual(summary(batch.entries), ["say \"hi\""])
        XCTAssertEqual(batch.skipped, 3)
    }

    func testWindowsLineEndingsBOMAndSurroundingSpaces() {
        let batch = WisprCSVParser.parse(data: Data("\u{FEFF}Wispr ,  PR\r\nPopuli\r\n".utf8))
        XCTAssertEqual(summary(batch.entries), ["Wispr → PR", "Populi"])
        XCTAssertEqual(batch.skipped, 0)
    }

    func testASpaceBeforeAQuoteKeepsTheQuotes() {
        XCTAssertEqual(summary(WisprCSVParser.parse("hello, \"world\"").entries), ["hello → \"world\""])
    }
}

final class WisprDatabaseTests: XCTestCase {
    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appending(path: "wispr-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    private static let personal = "00000000-0000-0000-0000-000000000000"
    private static let schema = """
    CREATE TABLE Dictionary (id VARCHAR(36) PRIMARY KEY, phrase VARCHAR(255) NOT NULL, replacement VARCHAR(255),
      teamDictionaryId VARCHAR(36) NOT NULL DEFAULT '\(personal)', frequencyUsed INTEGER NOT NULL DEFAULT 0,
      createdAt DATETIME NOT NULL, isDeleted TINYINT(1) NOT NULL DEFAULT 0, isSnippet TINYINT(1) NOT NULL DEFAULT 0,
      isStarred TINYINT(1) NOT NULL DEFAULT 0);
    INSERT INTO Dictionary (id, phrase, replacement, frequencyUsed, createdAt, isStarred) VALUES
      ('1', 'Kubernetes', NULL, 6, '2026-01-01 21:00:22.116 +00:00', 1),
      ('2', 'pee are', 'PR', 2, '2026-01-02 21:00:22.116 +00:00', 0);
    INSERT INTO Dictionary (id, phrase, replacement, createdAt, isSnippet) VALUES ('3', 'sig', 'Best, Rob', '2026-01-03 00:00:00.000 +00:00', 1);
    INSERT INTO Dictionary (id, phrase, createdAt, teamDictionaryId) VALUES ('4', 'TeamWord', '2026-01-03 00:00:00.000 +00:00', 'abc');
    INSERT INTO Dictionary (id, phrase, createdAt, isDeleted) VALUES ('5', 'Deleted', '2026-01-03 00:00:00.000 +00:00', 1);
    """

    private func open(_ url: URL) throws -> OpaquePointer {
        var db: OpaquePointer?
        guard sqlite3_open(url.path, &db) == SQLITE_OK, let db else { throw XCTSkip("cannot create test database") }
        return db
    }

    private func exec(_ db: OpaquePointer, _ sql: String) {
        XCTAssertEqual(sqlite3_exec(db, sql, nil, nil, nil), SQLITE_OK, String(cString: sqlite3_errmsg(db)))
    }

    private func makeDatabase(_ sql: String = schema, wal: Bool = false) throws -> URL {
        let url = dir.appending(path: "flow.sqlite")
        let db = try open(url)
        if wal { exec(db, "PRAGMA journal_mode=WAL;") }
        exec(db, sql)
        sqlite3_close(db)
        return url
    }

    private func leftoverSnapshots() -> [String] {
        let tmp = FileManager.default.temporaryDirectory.path
        return ((try? FileManager.default.contentsOfDirectory(atPath: tmp)) ?? []).filter { $0.hasPrefix("speak-wispr-") }
    }

    func testImportsOnlyLivePersonalNonSnippetEntries() throws {
        let entries = try WisprDatabaseReader.read(from: makeDatabase())

        XCTAssertEqual(entries.count, 2)
        let word = try XCTUnwrap(entries.first { $0.kind == .word })
        XCTAssertEqual(word.text, "Kubernetes")
        XCTAssertTrue(word.starred)
        XCTAssertEqual(word.useCount, 6)
        let replacement = try XCTUnwrap(entries.first { $0.kind == .replacement })
        XCTAssertEqual(replacement.heardAs, "pee are")
        XCTAssertEqual(replacement.text, "PR")
        XCTAssertEqual(replacement.useCount, 2)
        XCTAssertGreaterThan(replacement.addedAt, word.addedAt)
    }

    func testReadsAWALDatabaseLeftByAClosedApp() throws {
        // Wispr's SQLite removes -wal and -shm on close but keeps WAL mode in the header, which a plain
        // read-only open cannot read. Apple's SQLite keeps the (checkpointed) files, so remove them here.
        let url = try makeDatabase(wal: true)
        try? FileManager.default.removeItem(atPath: url.path + "-wal")
        try? FileManager.default.removeItem(atPath: url.path + "-shm")
        XCTAssertEqual(try WisprDatabaseReader.read(from: url).count, 2)
    }

    func testReadsRowsStillInTheWALWhileTheAppIsOpen() throws {
        let url = try makeDatabase(wal: true)
        let app = try open(url)
        defer { sqlite3_close(app) }
        exec(app, "PRAGMA wal_autocheckpoint=0;")
        exec(app, "INSERT INTO Dictionary (id, phrase, createdAt) VALUES ('6', 'Populi', '2026-01-04 00:00:00.000 +00:00');")
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path + "-wal"))

        XCTAssertTrue(try WisprDatabaseReader.read(from: url).contains { $0.text == "Populi" })
    }

    func testNeverChangesTheSourceDatabase() throws {
        let url = try makeDatabase()
        let before = try FileManager.default.attributesOfItem(atPath: url.path)
        let bytes = try Data(contentsOf: url)
        _ = try WisprDatabaseReader.read(from: url)

        let after = try FileManager.default.attributesOfItem(atPath: url.path)
        XCTAssertEqual(after[.modificationDate] as? Date, before[.modificationDate] as? Date)
        XCTAssertEqual(try Data(contentsOf: url), bytes)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: dir.path), ["flow.sqlite"])
        XCTAssertEqual(leftoverSnapshots(), [])
    }

    func testUnknownSchemaIsUnrecognizedAndLeavesNoSnapshot() throws {
        let url = try makeDatabase("CREATE TABLE Dictionary (id TEXT, phrase TEXT, isDeleted INT, isSnippet INT, teamDictionaryId TEXT);")
        XCTAssertThrowsError(try WisprDatabaseReader.read(from: url)) { XCTAssertEqual($0 as? WisprImportError, .unrecognized) }
        XCTAssertEqual(leftoverSnapshots(), [])
    }

    func testMissingDatabaseIsNotFound() {
        XCTAssertThrowsError(try WisprDatabaseReader.read(from: dir.appending(path: "nope.sqlite"))) {
            XCTAssertEqual($0 as? WisprImportError, .notFound)
        }
    }
}
