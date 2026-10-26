import Foundation

/// The keyboard's decisions, derived only from the shared files, so a recreated
/// keyboard view behaves the same (R7, KTD6).
public struct KeyboardResultSelector: Sendable {
    public enum MicAction: Equatable, Sendable {
        case openApp, start, stop, wait
    }

    public enum Outcome: Equatable, Sendable {
        case insert(String, cleanupSkipped: Bool)
        case error(String)
        case discarded
        /// For example, a clip too short to transcribe.
        case nothing
    }

    /// How long the keyboard waits on an in-flight request after the session died.
    /// Covers the 60 s transcription and 30 s cleanup timeouts.
    public static let maxWait: TimeInterval = 100

    public let state: FlowState
    public let command: FlowCommand
    public let now: Date

    public init(state: FlowState, command: FlowCommand, now: Date) {
        self.state = state
        self.command = command
        self.now = now
    }

    /// The pending request's result, ready to consume exactly once.
    public var resolution: (requestID: UUID, outcome: Outcome)? {
        guard let pending = command.pendingRequestID, let result = state.result, result.requestID == pending else { return nil }
        if command.abandoned { return (pending, .discarded) }
        if let text = result.text { return (pending, .insert(text, cleanupSkipped: result.cleanupSkipped)) }
        if let error = result.error { return (pending, .error(error)) }
        return (pending, .nothing)
    }

    public var micAction: MicAction {
        if resolution != nil { return .wait }
        let alive = state.isAlive(at: now)
        if let pending = command.pendingRequestID, state.activeRequestID == pending {
            if state.phase == .recording { return alive ? .stop : .openApp }
            let issued = command.issuedAt ?? .distantPast
            return alive || now.timeIntervalSince(issued) < Self.maxWait ? .wait : .openApp
        }
        guard alive else { return .openApp }
        return state.phase == .ready ? .start : .wait
    }

    /// Adds a leading space when the text before the cursor doesn't end in whitespace.
    public static func textToInsert(_ text: String, after context: String?) -> String {
        guard let last = context?.last, !last.isWhitespace else { return text }
        return " " + text
    }
}
