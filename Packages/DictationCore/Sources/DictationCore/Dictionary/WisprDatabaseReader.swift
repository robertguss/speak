import Foundation
import SQLite3

public enum WisprImportError: Error, Equatable {
    case notFound
    case unrecognized
    case unreadable(String)

    public var userMessage: String {
        switch self {
        case .notFound: "No Wispr Flow data found on this Mac. Import a CSV instead."
        case .unrecognized: "This Wispr Flow version isn't recognized. Import a CSV instead."
        case .unreadable(let detail): "Couldn't read the Wispr Flow data: \(detail)"
        }
    }
}

/// Reads the personal dictionary from Wispr Flow's local database (R8, R11, KTD7).
/// Wispr's files are only ever opened read-only; queries run against a private snapshot.
public enum WisprDatabaseReader {
    #if os(macOS)
    public static var defaultURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/Application Support/Wispr Flow/flow.sqlite")
    }
    #endif

    static let personalTeamID = "00000000-0000-0000-0000-000000000000"
    static let requiredColumns: Set = ["phrase", "replacement", "isDeleted", "isSnippet", "teamDictionaryId", "isStarred", "frequencyUsed"]

    public static func read(from source: URL) throws -> [DictionaryEntry] {
        guard FileManager.default.fileExists(atPath: source.path) else { throw WisprImportError.notFound }
        let folder = FileManager.default.temporaryDirectory.appending(path: "speak-wispr-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let snapshot = folder.appending(path: "snapshot.sqlite")

        do {
            try backup(source, to: snapshot, immutable: false)
        } catch where !FileManager.default.fileExists(atPath: source.path + "-wal") {
            // Wispr closed: its WAL-mode file has no -shm, which a read-only connection can't create.
            // Nothing is writing, so reading the file as immutable is safe.
            try? FileManager.default.removeItem(at: snapshot)
            try backup(source, to: snapshot, immutable: true)
        }
        return try entries(in: snapshot)
    }

    /// Copies a consistent snapshot with SQLite's backup API from a read-only connection.
    private static func backup(_ source: URL, to destination: URL, immutable: Bool) throws {
        let uri = source.absoluteString + (immutable ? "?mode=ro&immutable=1" : "?mode=ro")
        let from = try open(uri, flags: SQLITE_OPEN_READONLY | SQLITE_OPEN_URI)
        defer { sqlite3_close(from) }
        let to = try open(destination.path, flags: SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE)
        defer { sqlite3_close(to) }

        guard let backup = sqlite3_backup_init(to, "main", from, "main") else { throw unreadable(to) }
        let step = sqlite3_backup_step(backup, -1)
        sqlite3_backup_finish(backup)
        guard step == SQLITE_DONE else { throw WisprImportError.unreadable(String(cString: sqlite3_errstr(step))) }
    }

    private static func entries(in snapshot: URL) throws -> [DictionaryEntry] {
        // The snapshot keeps the source's WAL flag, which a read-only connection can't open without -shm.
        // It's a private copy, so open it read-write.
        let db = try open(snapshot.path, flags: SQLITE_OPEN_READWRITE)
        defer { sqlite3_close(db) }

        let columns = Set(try rows(db, "PRAGMA table_info(Dictionary)").compactMap { $0[1] })
        guard columns.isSuperset(of: requiredColumns) else { throw WisprImportError.unrecognized }
        let createdAt = columns.contains("createdAt") ? "createdAt" : "NULL"
        let sql = """
        SELECT phrase, replacement, isStarred, frequencyUsed, \(createdAt) FROM Dictionary
        WHERE isDeleted = 0 AND isSnippet = 0 AND teamDictionaryId = '\(personalTeamID)'
        """
        let now = Date()
        return try rows(db, sql).compactMap { row in
            let phrase = (row[0] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let replacement = (row[1] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !phrase.isEmpty else { return nil }
            return DictionaryEntry(
                kind: replacement.isEmpty ? .word : .replacement,
                text: replacement.isEmpty ? phrase : replacement,
                heardAs: phrase,
                starred: row[2] == "1",
                useCount: Int(row[3] ?? "") ?? 0,
                addedAt: row[4].flatMap(parseDate) ?? now
            )
        }
    }

    /// Wispr stores dates as text like `2026-01-01 21:00:22.116 +00:00`.
    private static func parseDate(_ text: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS xxx"
        return formatter.date(from: text)
    }

    private static func open(_ path: String, flags: Int32) throws -> OpaquePointer {
        var db: OpaquePointer?
        guard sqlite3_open_v2(path, &db, flags, nil) == SQLITE_OK, let db else {
            defer { sqlite3_close(db) }
            throw unreadable(db)
        }
        return db
    }

    /// Every row as text columns.
    private static func rows(_ db: OpaquePointer, _ sql: String) throws -> [[String?]] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { throw unreadable(db) }
        defer { sqlite3_finalize(statement) }
        var rows: [[String?]] = []
        while true {
            let status = sqlite3_step(statement)
            guard status == SQLITE_ROW else {
                guard status == SQLITE_DONE else { throw unreadable(db) }
                return rows
            }
            rows.append((0..<sqlite3_column_count(statement)).map { column in
                sqlite3_column_text(statement, column).map { String(cString: $0) }
            })
        }
    }

    private static func unreadable(_ db: OpaquePointer?) -> WisprImportError {
        .unreadable(db.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown error")
    }
}
