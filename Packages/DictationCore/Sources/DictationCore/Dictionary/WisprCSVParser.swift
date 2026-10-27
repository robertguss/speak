import Foundation

public struct ImportBatch: Equatable, Sendable {
    public var entries: [DictionaryEntry]
    public var skipped: Int

    public init(entries: [DictionaryEntry], skipped: Int) {
        self.entries = entries
        self.skipped = skipped
    }
}

public enum WisprCSVParser {
    public static func parse(data: Data) -> ImportBatch {
        parse(String(decoding: data, as: UTF8.self))
    }

    public static func parse(_ text: String) -> ImportBatch {
        var lines = text.drop { $0 == "\u{FEFF}" }.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
        if lines.last?.isEmpty == true { lines.removeLast() }

        var batch = ImportBatch(entries: [], skipped: 0)
        for line in lines {
            guard var fields = fields(line)?.map({ $0.trimmingCharacters(in: .whitespaces) }) else {
                batch.skipped += 1
                continue
            }
            while fields.last?.isEmpty == true { fields.removeLast() }
            switch fields.count {
            case 1: batch.entries.append(.word(fields[0]))
            case 2 where !fields[0].isEmpty: batch.entries.append(.replacement(fields[0], with: fields[1]))
            default: batch.skipped += 1
            }
        }
        return batch
    }

    /// A field is quoted only when its quote comes right after the comma, as in Wispr's own importer.
    private static func fields(_ line: Substring) -> [String]? {
        var fields: [String] = []
        var rest = line[...]
        while true {
            var field = ""
            if rest.first == "\"" {
                rest = rest.dropFirst()
                while true {
                    guard let quote = rest.firstIndex(of: "\"") else { return nil }
                    field += rest[..<quote]
                    rest = rest[rest.index(after: quote)...]
                    guard rest.first == "\"" else { break }
                    field += "\""
                    rest = rest.dropFirst()
                }
                rest = rest.drop { $0 != "," }
            } else {
                field = String(rest.prefix { $0 != "," })
                rest = rest.drop { $0 != "," }
            }
            fields.append(field)
            guard rest.first == "," else { return fields }
            rest = rest.dropFirst()
        }
    }
}
