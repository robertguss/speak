import Foundation

/// Applies "heard as → write as" replacements to finished text (R7, KTD5).
public enum DictionaryReplacer {
    /// Whole-word, case-insensitive, longest phrase first, in one pass so replaced text is never matched again.
    public static func apply(to text: String, entries: [DictionaryEntry]) -> String {
        let replacements = entries
            .compactMap { entry -> (words: [String], text: String)? in
                let words = (entry.heardAs ?? "").split(whereSeparator: \.isWhitespace).map(String.init)
                return entry.kind == .replacement && !words.isEmpty ? (words, entry.text) : nil
            }
            .sorted { $0.words.joined(separator: " ").count > $1.words.joined(separator: " ").count }
        guard !replacements.isEmpty else { return text }

        let alternatives = replacements
            .map { "(" + $0.words.map(NSRegularExpression.escapedPattern(for:)).joined(separator: "\\s+") + ")" }
            .joined(separator: "|")
        // A match may not touch a letter or digit on either side.
        let pattern = "(?<![\\p{L}\\p{N}])(?:\(alternatives))(?![\\p{L}\\p{N}])"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return text }

        let source = text as NSString
        var result = ""
        var cursor = 0
        for match in regex.matches(in: text, range: NSRange(location: 0, length: source.length)) {
            guard let group = (1...replacements.count).first(where: { match.range(at: $0).location != NSNotFound }) else { continue }
            result += source.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
            result += replacements[group - 1].text
            cursor = match.range.location + match.range.length
        }
        return result + source.substring(from: cursor)
    }
}
