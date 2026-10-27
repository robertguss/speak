import XCTest
@testable import DictationCore

final class VocabularyHintsTests: XCTestCase {
    private func words(_ texts: [String]) -> [DictionaryEntry] {
        texts.map { .word($0) }
    }

    func testReplacementsContributeTheirOutputNeverWhatIsHeard() {
        let hints = VocabularyHints.select([.replacement("pee are", with: "PR"), .word("Kubernetes")], provider: .openAICompatible, model: "gpt-transcribe")
        XCTAssertEqual(hints.terms, ["PR", "Kubernetes"])
    }

    func testTermsAreDeduplicatedIgnoringCase() {
        let hints = VocabularyHints.select([.word("PR"), .replacement("pee are", with: "pr"), .word("Kubernetes")], provider: .elevenLabs, model: "scribe_v2")
        XCTAssertEqual(hints.terms, ["PR", "Kubernetes"])
        XCTAssertEqual(hints.candidateCount, 2)
    }

    func testGPTTranscribeDropsTermsTheAPIRejectsAndCapsAt100() {
        let hints = VocabularyHints.select(words(["a<b", "ok", "c>d"]), provider: .openAICompatible, model: "gpt-transcribe")
        XCTAssertEqual(hints.terms, ["ok"])

        let many = VocabularyHints.select(words((0..<300).map { "term\($0)" }), provider: .openAICompatible, model: "gpt-transcribe")
        XCTAssertEqual(many.terms.count, 100)
        XCTAssertEqual(many.terms.first, "term0")
        XCTAssertEqual(many.candidateCount, 300)
    }

    func testWhisperPromptStaysShortAndKeepsHighestPriorityTerms() {
        let terms = (0..<300).map { "term\($0)" }
        let hints = VocabularyHints.select(words(terms), provider: .openAICompatible, model: "whisper-large-v3-turbo")
        let prompt = VocabularyHints.whisperPrompt(hints.terms)

        XCTAssertLessThanOrEqual(prompt.count, 600)
        XCTAssertTrue(prompt.hasPrefix("Vocabulary: term0, term1, "))
        XCTAssertFalse(prompt.contains("term299"))
        XCTAssertEqual(hints.terms, Array(terms.prefix(hints.terms.count)))
    }

    func testDeepgramNova3StaysUnderTheTokenBudgetAndOtherModelsGetNothing() {
        let terms = (0..<300).map { String(format: "keyterm%03d", $0) }
        let nova3 = VocabularyHints.select(words(terms), provider: .deepgram, model: "nova-3")
        XCTAssertEqual(nova3.terms.count, 100)
        XCTAssertLessThanOrEqual(nova3.terms.reduce(0) { $0 + ($1.count + 2) / 3 }, 400)
        XCTAssertTrue(nova3.supported)

        let nova2 = VocabularyHints.select(words(terms), provider: .deepgram, model: "nova-2-general")
        XCTAssertEqual(nova2.terms, [])
        XCTAssertFalse(nova2.supported)
    }

    func testElevenLabsDropsLongOrManyWordOrBracketedTermsAndCapsAt100() {
        let long = String(repeating: "x", count: 60)
        let sixWords = "one two three four five six"
        let hints = VocabularyHints.select(words([long, sixWords, "a{b}", "five words are fine here", "Populi"]), provider: .elevenLabs, model: "scribe_v2")
        XCTAssertEqual(hints.terms, ["five words are fine here", "Populi"])

        let many = VocabularyHints.select(words((0..<300).map { "term\($0)" }), provider: .elevenLabs, model: "scribe_v2")
        XCTAssertEqual(many.terms.count, 100)
    }

    func testCleanupGlossaryIsCappedInPriorityOrder() {
        let glossary = VocabularyHints.glossary(words((0..<1000).map { "term\($0)" }))
        XCTAssertLessThanOrEqual(glossary.joined(separator: ", ").count, 2000)
        XCTAssertEqual(glossary.first, "term0")
        XCTAssertFalse(glossary.contains("term999"))
    }
}
