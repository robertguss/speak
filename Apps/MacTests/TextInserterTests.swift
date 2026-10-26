import XCTest
@testable import Dictation

final class TextInserterTests: XCTestCase {
    func testHostAppLoads() {
        XCTAssertNotNil(Bundle.main.bundleIdentifier)
    }
}
