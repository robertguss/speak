import XCTest
@testable import DictationCore

final class DictionaryReplacerTests: XCTestCase {
    private func replace(_ text: String, _ entries: [DictionaryEntry]) -> String {
        DictionaryReplacer.apply(to: text, entries: entries)
    }

    func testReplacesWholeWordsOnly() {
        let pr = DictionaryEntry.replacement("pee are", with: "PR")
        XCTAssertEqual(replace("open a pee are for the fix", [pr]), "open a PR for the fix")
        XCTAssertEqual(replace("peeare, spee are, pee arena, 2pee are", [pr]), "peeare, spee are, pee arena, 2pee are")
        XCTAssertEqual(replace("pee are.", [pr]), "PR.")
    }

    func testMatchesIgnoringCaseAndWritesTheStoredText() {
        XCTAssertEqual(replace("Pee Are first, then PEE ARE again", [.replacement("pee are", with: "PR")]), "PR first, then PR again")
    }

    func testLongerHeardAsWinsOverItsPrefix() {
        let entries: [DictionaryEntry] = [.replacement("pee are", with: "PR"), .replacement("pee are review", with: "PR review")]
        XCTAssertEqual(replace("pee are review pending", entries), "PR review pending")
        XCTAssertEqual(replace("pee are review pending", entries.reversed()), "PR review pending")
    }

    func testOutputIsNotReplacedAgain() {
        let entries: [DictionaryEntry] = [.replacement("cube cuddle", with: "kubectl"), .replacement("kubectl", with: "WRONG")]
        XCTAssertEqual(replace("run cube cuddle", entries), "run kubectl")
    }

    func testSpecialCharactersAreLiteral() {
        let entries: [DictionaryEntry] = [.replacement("see plus plus", with: "C++"), .replacement("dollar home", with: "$HOME"), .replacement("a.b", with: "\\1")]
        XCTAssertEqual(replace("see plus plus in dollar home and axb a.b", entries), "C++ in $HOME and axb \\1")
    }

    func testWordsAndEmptyHeardAsAreIgnored() {
        let entries: [DictionaryEntry] = [.word("PR"), DictionaryEntry(kind: .replacement, text: "X", heardAs: "  ")]
        XCTAssertEqual(replace("pr stays as dictated", entries), "pr stays as dictated")
    }
}
