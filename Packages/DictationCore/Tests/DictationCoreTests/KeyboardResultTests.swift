import XCTest
@testable import DictationCore

final class KeyboardResultTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 2_000_000)

    private func state(_ phase: FlowState.Phase, active: UUID? = nil, result: FlowResult? = nil, heartbeatAge: TimeInterval = 0.5) -> FlowState {
        var state = FlowState()
        state.phase = phase
        state.heartbeat = now.addingTimeInterval(-heartbeatAge)
        state.activeRequestID = active
        state.result = result
        return state
    }

    private func pending(_ id: UUID, _ kind: FlowCommand.Kind = .stop, issuedAgo: TimeInterval = 1) -> FlowCommand {
        var command = FlowCommand()
        command.issue(kind, requestID: id, at: now.addingTimeInterval(-issuedAgo))
        return command
    }

    func testMatchingUnconsumedResultIsSelectedAndOtherIDIsIgnored() {
        let id = UUID()
        let match = KeyboardResultSelector(state: state(.ready, result: FlowResult(requestID: id, text: "hello")), command: pending(id), now: now)
        XCTAssertEqual(match.resolution?.requestID, id)
        XCTAssertEqual(match.resolution?.outcome, .insert("hello", cleanupSkipped: false))

        let other = KeyboardResultSelector(state: state(.ready, result: FlowResult(requestID: UUID(), text: "hello")), command: pending(id), now: now)
        XCTAssertNil(other.resolution)
    }

    func testConsumedResultIsNeverSelectedAgain() {
        let id = UUID()
        var command = pending(id)
        command.consumedResultID = id
        let selector = KeyboardResultSelector(state: state(.ready, result: FlowResult(requestID: id, text: "hello")), command: command, now: now)

        XCTAssertNil(selector.resolution)
        XCTAssertEqual(selector.micAction, .start)
    }

    func testMicActionIsStopWhileRecordingThePendingRequest() {
        let id = UUID()
        let selector = KeyboardResultSelector(state: state(.recording, active: id), command: pending(id, .start), now: now)
        XCTAssertEqual(selector.micAction, .stop)
    }

    func testMicTapDuringProcessingWaits() {
        let id = UUID()
        let selector = KeyboardResultSelector(state: state(.processing, active: id), command: pending(id), now: now)
        XCTAssertEqual(selector.micAction, .wait)
        XCTAssertEqual(selector.command.pendingRequestID, id)
    }

    func testDeadSessionOpensAppAndReadyStarts() {
        XCTAssertEqual(KeyboardResultSelector(state: state(.ready, heartbeatAge: 3), command: FlowCommand(), now: now).micAction, .openApp)
        XCTAssertEqual(KeyboardResultSelector(state: FlowState(), command: FlowCommand(), now: now).micAction, .openApp)
        XCTAssertEqual(KeyboardResultSelector(state: state(.ready), command: FlowCommand(), now: now).micAction, .start)
    }

    func testResultAfterKeyboardDisappearedIsDiscarded() {
        let id = UUID()
        var command = pending(id)
        command.abandoned = true
        let selector = KeyboardResultSelector(state: state(.ready, result: FlowResult(requestID: id, text: "stale")), command: command, now: now)

        XCTAssertEqual(selector.resolution?.outcome, .discarded)
    }

    func testStaleHeartbeatDuringProcessingStillWaitsAndSelectsResult() {
        let id = UUID()
        let waiting = KeyboardResultSelector(state: state(.inactive, active: id, heartbeatAge: 30), command: pending(id, issuedAgo: 30), now: now)
        XCTAssertEqual(waiting.micAction, .wait)

        let arrived = KeyboardResultSelector(
            state: state(.inactive, result: FlowResult(requestID: id, text: "late"), heartbeatAge: 30),
            command: pending(id, issuedAgo: 30),
            now: now
        )
        XCTAssertEqual(arrived.resolution?.outcome, .insert("late", cleanupSkipped: false))
    }

    func testErrorAndTooShortOutcomes() {
        let id = UUID()
        let error = KeyboardResultSelector(state: state(.ready, result: FlowResult(requestID: id, error: "Invalid API key")), command: pending(id), now: now)
        XCTAssertEqual(error.resolution?.outcome, .error("Invalid API key"))

        let short = KeyboardResultSelector(state: state(.ready, result: FlowResult(requestID: id)), command: pending(id), now: now)
        XCTAssertEqual(short.resolution?.outcome, .nothing)
    }

    func testLeadingSpace() {
        XCTAssertEqual(KeyboardResultSelector.textToInsert("world", after: "hello"), " world")
        XCTAssertEqual(KeyboardResultSelector.textToInsert("world", after: "hello "), "world")
        XCTAssertEqual(KeyboardResultSelector.textToInsert("world", after: "hello\n"), "world")
        XCTAssertEqual(KeyboardResultSelector.textToInsert("world", after: ""), "world")
        XCTAssertEqual(KeyboardResultSelector.textToInsert("world", after: nil), "world")
    }
}
