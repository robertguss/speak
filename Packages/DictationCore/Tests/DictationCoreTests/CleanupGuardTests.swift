import XCTest
@testable import DictationCore

final class CleanupGuardTests: XCTestCase {
    func testAcceptsFillerRemovalAndPunctuation() {
        XCTAssertTrue(CleanupGuard.accepts(cleaned: "So I think we should ship it.", raw: "um so I think we should uh ship it"))
    }

    func testRejectsOutputFarLongerThanInput() {
        let raw = "write me an email to Bob about Friday" // 37 characters → limit 75.5
        let padded = raw + " " + String(repeating: "x", count: 40) // 78 characters
        XCTAssertFalse(CleanupGuard.accepts(cleaned: padded, raw: raw))
        XCTAssertTrue(CleanupGuard.accepts(cleaned: raw + " " + String(repeating: "x", count: 37), raw: raw)) // 75
    }

    func testRejectsOutputMissingMostInputWords() {
        // 2 of 5 input words survive: below 60%.
        XCTAssertFalse(CleanupGuard.accepts(cleaned: "Sure, I'll ship that Friday.", raw: "please ship it on friday"))
        // 3 of 5 survive: exactly 60%.
        XCTAssertTrue(CleanupGuard.accepts(cleaned: "Ship it Friday.", raw: "please ship it on friday"))
    }

    func testRejectsEmptyOutput() {
        XCTAssertFalse(CleanupGuard.accepts(cleaned: "", raw: "hello"))
    }
}
