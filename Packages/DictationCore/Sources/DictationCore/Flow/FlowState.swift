import Foundation

/// The outcome of one keyboard request, written by the app (KTD6).
public struct FlowResult: Codable, Equatable, Sendable {
    public var requestID: UUID
    /// Removed once the keyboard consumes it or the session ends (R15).
    public var text: String?
    public var error: String?
    public var cleanupSkipped = false

    public init(requestID: UUID, text: String? = nil, error: String? = nil, cleanupSkipped: Bool = false) {
        self.requestID = requestID
        self.text = text
        self.error = error
        self.cleanupSkipped = cleanupSkipped
    }
}

/// `state.json`, written only by the iOS app (KTD6).
public struct FlowState: Codable, Equatable, Sendable {
    public enum Phase: String, Codable, Sendable {
        case inactive, ready, recording, processing
    }

    public static let heartbeatTimeout: TimeInterval = 2

    public var phase = Phase.inactive
    /// Updated every second while the session is active.
    public var heartbeat: Date?
    /// The request being recorded or transcribed. It survives the end of a session
    /// so an interrupted request still delivers its result.
    public var activeRequestID: UUID?
    public var result: FlowResult?
    /// Why the last session couldn't start, for the keyboard's status line.
    public var sessionError: String?

    public init() {}

    public func isAlive(at now: Date) -> Bool {
        guard phase != .inactive, let heartbeat else { return false }
        return now.timeIntervalSince(heartbeat) < Self.heartbeatTimeout
    }
}

/// `command.json`, written only by the keyboard (KTD6).
public struct FlowCommand: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case start, stop, cancel
    }

    public var kind: Kind?
    public var requestID: UUID?
    public var issuedAt: Date?
    /// The keyboard disappeared before this request's result arrived.
    public var abandoned = false
    public var consumedResultID: UUID?

    public init() {}

    /// The request the keyboard still waits on, if any.
    public var pendingRequestID: UUID? {
        requestID == consumedResultID ? nil : requestID
    }

    public mutating func issue(_ kind: Kind, requestID: UUID, at date: Date) {
        self.kind = kind
        self.requestID = requestID
        issuedAt = date
        abandoned = false
    }
}
