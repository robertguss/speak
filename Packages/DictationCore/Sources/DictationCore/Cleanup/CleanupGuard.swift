import Foundation

/// Rejects cleanup output that no longer looks like the dictation (R13, KTD11):
/// much longer than the input, or missing too many of the input's words.
public enum CleanupGuard {
    public static func accepts(cleaned: String, raw: String) -> Bool {
        guard !cleaned.isEmpty else { return false }
        guard Double(cleaned.count) <= Double(raw.count) * 1.5 + 20 else { return false }
        let inputWords = words(raw)
        guard !inputWords.isEmpty else { return true }
        let outputWords = Set(words(cleaned))
        let kept = inputWords.filter(outputWords.contains).count
        return Double(kept) >= Double(inputWords.count) * 0.6
    }

    static func words(_ text: String) -> [String] {
        text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "'")).inverted)
            .filter { !$0.isEmpty }
    }
}
