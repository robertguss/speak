import XCTest
@testable import DictationCore

final class HotkeyStateMachineTests: XCTestCase {
    private func run(_ events: [HotkeyStateMachine.Event]) -> [HotkeyStateMachine.Action?] {
        var machine = HotkeyStateMachine()
        return events.map { machine.handle($0) }
    }

    func testQuickTapLatchesAndNextDownStops() {
        XCTAssertEqual(run([.keyDown(at: 10), .keyUp(at: 10.12), .keyDown(at: 14), .keyUp(at: 14.05)]), [.start, nil, .stop, nil])
    }

    func testHoldPastThresholdStopsOnRelease() {
        XCTAssertEqual(run([.keyDown(at: 10), .keyUp(at: 10.45)]), [.start, .stop])
    }

    func testThresholdBoundary() {
        XCTAssertEqual(run([.keyDown(at: 0), .keyUp(at: 0.299)]), [.start, nil])
        XCTAssertEqual(run([.keyDown(at: 0), .keyUp(at: 0.3)]), [.start, .stop])
    }

    func testOtherKeyWhileDownCancelsAndReleaseEmitsNothing() {
        XCTAssertEqual(run([.keyDown(at: 0), .otherKey, .keyUp(at: 0.1)]), [.start, .cancel, nil])
        XCTAssertEqual(run([.keyDown(at: 0), .otherKey, .keyUp(at: 2), .keyDown(at: 3)]), [.start, .cancel, nil, .start])
    }

    func testOtherKeyWhileLatchedDoesNotCancel() {
        XCTAssertEqual(run([.keyDown(at: 0), .keyUp(at: 0.1), .otherKey, .keyDown(at: 5)]), [.start, nil, nil, .stop])
    }

    func testSecondDownWhileLatchedStopsOnceAndItsReleaseEmitsNothing() {
        XCTAssertEqual(
            run([.keyDown(at: 0), .keyUp(at: 0.1), .keyDown(at: 5), .keyDown(at: 5.05), .keyUp(at: 6), .keyUp(at: 6.1)]),
            [.start, nil, .stop, nil, nil, nil]
        )
    }

    func testReleaseWithoutPriorDownEmitsNothing() {
        XCTAssertEqual(run([.keyUp(at: 1), .keyDown(at: 2), .keyUp(at: 3)]), [nil, .start, .stop])
    }
}
