import XCTest
@testable import DictationCore

final class FlowStateTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_000_000)
    private var files: FlowFiles!

    override func setUpWithError() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "flow-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        files = FlowFiles(directory: dir)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: files.directory)
    }

    private func command(_ kind: FlowCommand.Kind, _ id: UUID, at date: Date) -> FlowCommand {
        var command = FlowCommand()
        command.issue(kind, requestID: id, at: date)
        return command
    }

    private func readyPolicy(timeout: TimeInterval = 300) -> FlowSessionPolicy {
        var policy = FlowSessionPolicy(idleTimeout: timeout)
        policy.sessionStarted(at: t0)
        return policy
    }

    func testFilesRoundTripAndStaleHeartbeatMeansDead() throws {
        var state = FlowState()
        state.phase = .ready
        state.heartbeat = t0
        state.result = FlowResult(requestID: UUID(), text: "hi", cleanupSkipped: true)
        try files.write(state)
        let id = UUID()
        try files.write(command(.start, id, at: t0))

        XCTAssertEqual(files.readState(), state)
        XCTAssertEqual(files.readCommand().requestID, id)
        XCTAssertTrue(state.isAlive(at: t0.addingTimeInterval(1.9)))
        XCTAssertFalse(state.isAlive(at: t0.addingTimeInterval(2.1)))
    }

    func testHeartbeatWriteLeavesCommandFileUnchanged() throws {
        try files.write(command(.stop, UUID(), at: t0))
        let before = try Data(contentsOf: files.commandURL)

        var policy = readyPolicy()
        policy.beat(at: t0.addingTimeInterval(1))
        try files.write(policy.state)

        XCTAssertEqual(try Data(contentsOf: files.commandURL), before)
    }

    func testStartWhileProcessingIsIgnored() {
        var policy = readyPolicy()
        let first = UUID()
        XCTAssertEqual(policy.handle(command(.start, first, at: t0), at: t0), .beginClip)
        XCTAssertEqual(policy.handle(command(.stop, first, at: t0), at: t0), .finishClip(first))

        XCTAssertNil(policy.handle(command(.start, UUID(), at: t0), at: t0))
        XCTAssertEqual(policy.state.phase, .processing)
        XCTAssertEqual(policy.state.activeRequestID, first)
    }

    func testStaleStartCommandIsIgnored() {
        var policy = readyPolicy()
        XCTAssertNil(policy.handle(command(.start, UUID(), at: t0.addingTimeInterval(-10)), at: t0))
        XCTAssertEqual(policy.state.phase, .ready)
    }

    func testStopForAnotherRequestIsIgnored() {
        var policy = readyPolicy()
        let id = UUID()
        _ = policy.handle(command(.start, id, at: t0), at: t0)

        XCTAssertNil(policy.handle(command(.stop, UUID(), at: t0), at: t0))
        XCTAssertEqual(policy.state.phase, .recording)
    }

    func testResultCarriesTheStopsRequestIDAndConsumedDropsText() {
        var policy = readyPolicy()
        let id = UUID()
        _ = policy.handle(command(.start, id, at: t0), at: t0)
        _ = policy.handle(command(.stop, id, at: t0), at: t0)
        policy.finish(id, text: "hello world", at: t0)

        XCTAssertEqual(policy.state.result, FlowResult(requestID: id, text: "hello world"))
        XCTAssertEqual(policy.state.phase, .ready)

        var consumed = command(.stop, id, at: t0)
        consumed.consumedResultID = id
        XCTAssertNil(policy.handle(consumed, at: t0))
        XCTAssertEqual(policy.state.result?.requestID, id)
        XCTAssertNil(policy.state.result?.text)
    }

    func testEndingSessionClearsUnconsumedText() {
        var policy = readyPolicy()
        let id = UUID()
        _ = policy.handle(command(.start, id, at: t0), at: t0)
        _ = policy.handle(command(.stop, id, at: t0), at: t0)
        policy.finish(id, text: "secret", at: t0)

        policy.endSession()

        XCTAssertEqual(policy.state.phase, .inactive)
        XCTAssertNil(policy.state.result?.text)
    }

    func testInterruptedRecordingStillDeliversItsResult() {
        var policy = readyPolicy()
        let id = UUID()
        _ = policy.handle(command(.start, id, at: t0), at: t0)

        XCTAssertEqual(policy.endSession(), id)
        policy.finish(id, text: "late", at: t0)

        XCTAssertEqual(policy.state.phase, .inactive)
        XCTAssertEqual(policy.state.result, FlowResult(requestID: id, text: "late"))
    }

    func testAbandonedRequestResultHasNoText() {
        var policy = readyPolicy()
        let id = UUID()
        _ = policy.handle(command(.start, id, at: t0), at: t0)
        _ = policy.handle(command(.stop, id, at: t0), at: t0)
        var abandoned = command(.stop, id, at: t0)
        abandoned.abandoned = true
        _ = policy.handle(abandoned, at: t0)
        policy.finish(id, text: "do not keep", at: t0)

        XCTAssertNil(policy.state.result?.text)
    }

    func testIdleTimeoutCountsFromStartThenFromLastDictation() {
        var policy = readyPolicy(timeout: 300)
        XCTAssertFalse(policy.idleExpired(at: t0.addingTimeInterval(299)))
        XCTAssertTrue(policy.idleExpired(at: t0.addingTimeInterval(300)))

        let id = UUID()
        let t1 = t0.addingTimeInterval(200)
        _ = policy.handle(command(.start, id, at: t1), at: t1)
        _ = policy.handle(command(.stop, id, at: t1), at: t1)
        policy.finish(id, text: "x", at: t1)

        XCTAssertFalse(policy.idleExpired(at: t0.addingTimeInterval(300)))
        XCTAssertFalse(policy.idleExpired(at: t1.addingTimeInterval(299)))
        XCTAssertTrue(policy.idleExpired(at: t1.addingTimeInterval(300)))
    }

    func testRestartingAppDropsLeftoverText() {
        var state = FlowState()
        state.phase = .ready
        state.result = FlowResult(requestID: UUID(), text: "left over")
        let policy = FlowSessionPolicy(state: state, idleTimeout: 300)

        XCTAssertEqual(policy.state.phase, .inactive)
        XCTAssertNil(policy.state.result?.text)
    }
}
