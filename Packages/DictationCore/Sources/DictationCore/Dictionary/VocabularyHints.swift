import Foundation

/// Which dictionary terms a transcription request carries, by provider and model (R4, R5, KTD3, KTD4).
public struct VocabularyHints: Equatable, Sendable {
    /// Terms to send, highest priority first.
    public let terms: [String]
    /// How many distinct terms the dictionary has to offer.
    public let candidateCount: Int
    /// Whether the selected model takes hints at all.
    public let supported: Bool

    static let whisperPromptLimit = 600
    static let deepgramTokenBudget = 400
    static let glossaryLimit = 2000

    /// `entries` must already be in priority order, as `DictionaryStore.entries()` returns them.
    public static func select(_ entries: [DictionaryEntry], provider: TranscriptionProviderID, model: String) -> VocabularyHints {
        let candidates = candidates(entries)
        let terms: [String]?
        switch provider {
        case .openAICompatible where usesKeywords(model):
            terms = Array(candidates.filter { !$0.contains { "<>".contains($0) || $0.isNewline } }.prefix(100))
        case .openAICompatible:
            terms = fitting(candidates.filter { !$0.contains(where: \.isNewline) }) { whisperPrompt($0).count <= whisperPromptLimit }
        case .deepgram where model.hasPrefix("nova-3"):
            terms = fitting(candidates) { $0.reduce(0) { $0 + estimatedTokens($1) } <= deepgramTokenBudget }
        case .elevenLabs where model.hasPrefix("scribe_v2"):
            terms = Array(candidates.filter(elevenLabsAccepts).prefix(100))
        default:
            terms = nil
        }
        return VocabularyHints(terms: terms ?? [], candidateCount: candidates.count, supported: terms != nil)
    }

    /// `gpt-transcribe` takes `keywords[]`; other OpenAI-compatible models only take a prompt.
    static func usesKeywords(_ model: String) -> Bool {
        model.hasPrefix("gpt-transcribe")
    }

    /// The spelling list Whisper-style models receive as their prompt.
    static func whisperPrompt(_ terms: [String]) -> String {
        "Vocabulary: \(terms.joined(separator: ", "))."
    }

    /// Preferred spellings for the cleanup prompt (KTD6), capped in priority order.
    public static func glossary(_ entries: [DictionaryEntry]) -> [String] {
        fitting(candidates(entries)) { $0.joined(separator: ", ").count <= glossaryLimit }
    }

    /// Every word's text and every replacement's output; what is heard is a mishearing and never sent.
    static func candidates(_ entries: [DictionaryEntry]) -> [String] {
        var seen = Set<String>()
        return entries
            .map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && seen.insert($0.lowercased()).inserted }
    }

    /// The longest priority-order prefix that still satisfies `fits`.
    private static func fitting(_ terms: [String], _ fits: ([String]) -> Bool) -> [String] {
        var kept: [String] = []
        for term in terms {
            guard fits(kept + [term]) else { break }
            kept.append(term)
        }
        return kept
    }

    /// Deepgram's tokenizer isn't public; one token per 3 characters, rounded up, errs high.
    private static func estimatedTokens(_ term: String) -> Int {
        (term.count + 2) / 3
    }

    private static func elevenLabsAccepts(_ term: String) -> Bool {
        term.count < 50
            && term.split(whereSeparator: \.isWhitespace).count <= 5
            && !term.contains(where: "<>{}[]\\".contains)
    }
}
