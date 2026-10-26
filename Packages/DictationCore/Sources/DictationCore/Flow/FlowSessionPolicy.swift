import Foundation

/// The app's session rules: which keyboard commands to accept, when the idle timeout
/// fires, and when result text is cleared (R7, R8, R15). `FlowSessionController` drives it
/// with real timers, audio, and files.
public struct FlowSessionPolicy: Sendable {
    public enum Effect: Equatable, Sendable {
        case beginClip
        case finishClip(UUID)
        case discardClip
    }

    /// A start command older than this is stale (for example, left over from an earlier session).
    public static let startCommandLifetime: TimeInterval = 3

    public private(set) var state: FlowState
    public var idleTimeout: TimeInterval
    private var lastActivity = Date.distantPast
    private var abandonedID: UUID?

    /// Starts from the last written state, with any previous session ended and its text dropped.
    public init(state: FlowState = FlowState(), idleTimeout: TimeInterval) {
        self.state = state
        self.idleTimeout = idleTimeout
        self.state.phase = .inactive
        self.state.heartbeat = nil
        self.state.activeRequestID = nil
        self.state.result?.text = nil
    }

    public mutating func sessionStarted(at now: Date) {
        state.phase = .ready
        state.heartbeat = now
        state.sessionError = nil
        lastActivity = now
    }

    public mutating func sessionFailed(_ message: String) {
        state.phase = .inactive
        state.heartbeat = nil
        state.sessionError = message
    }

    public mutating func beat(at now: Date) {
        if state.phase != .inactive { state.heartbeat = now }
    }

    /// True when the session has sat ready, with no dictation, for the idle timeout.
    public func idleExpired(at now: Date) -> Bool {
        state.phase == .ready && now.timeIntervalSince(lastActivity) >= idleTimeout
    }

    public mutating func handle(_ command: FlowCommand, at now: Date) -> Effect? {
        if let consumed = command.consumedResultID, state.result?.requestID == consumed {
            state.result?.text = nil
        }
        if command.abandoned, let id = command.requestID {
            abandonedID = id
            if state.result?.requestID == id { state.result?.text = nil }
        }
        guard let kind = command.kind, let id = command.requestID else { return nil }

        switch kind {
        case .start:
            // The keyboard writes consumedResultID for a start it gave up waiting on.
            guard state.phase == .ready, !command.abandoned, command.consumedResultID != id,
                  let issued = command.issuedAt, now.timeIntervalSince(issued) < Self.startCommandLifetime,
                  id != state.result?.requestID else { return nil }
            state.phase = .recording
            state.activeRequestID = id
            return .beginClip
        case .stop:
            guard state.phase == .recording, state.activeRequestID == id else { return nil }
            state.phase = .processing
            return .finishClip(id)
        case .cancel:
            guard state.phase == .recording, state.activeRequestID == id else { return nil }
            state.phase = .ready
            state.activeRequestID = nil
            lastActivity = now
            return .discardClip
        }
    }

    /// Records the outcome of a request. All-nil means a clip too short to transcribe.
    public mutating func finish(_ id: UUID, text: String? = nil, error: String? = nil, cleanupSkipped: Bool = false, at now: Date) {
        guard state.activeRequestID == id else { return }
        state.result = FlowResult(requestID: id, text: abandonedID == id ? nil : text, error: error, cleanupSkipped: cleanupSkipped)
        state.activeRequestID = nil
        if state.phase != .inactive { state.phase = .ready }
        lastActivity = now
    }

    /// Ends the session and clears unconsumed text. Returns the request whose captured
    /// audio should still be transcribed, if one was recording.
    @discardableResult
    public mutating func endSession() -> UUID? {
        let recording = state.phase == .recording ? state.activeRequestID : nil
        state.phase = .inactive
        state.heartbeat = nil
        state.result?.text = nil
        return recording
    }
}
