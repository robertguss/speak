import Foundation

/// Tap-versus-hold logic for the Mac dictation key (KTD3).
///
/// Key down always starts recording, so hold-to-talk loses no speech. Releasing before
/// `holdThreshold` latches toggle mode and the next key down stops; releasing later stops.
/// Another key pressed while the dictation key is down cancels, so normal shortcuts keep working.
public struct HotkeyStateMachine: Sendable {
    public enum Event: Sendable, Equatable {
        case keyDown(at: TimeInterval)
        case keyUp(at: TimeInterval)
        case otherKey
    }

    public enum Action: Sendable, Equatable {
        case start
        case stop
        case cancel
    }

    enum State: Equatable {
        case idle
        case down(since: TimeInterval)
        case latched
        /// Recording already ended; swallow the matching key up.
        case awaitingRelease
    }

    public static let holdThreshold: TimeInterval = 0.3

    private(set) var state = State.idle

    public init() {}

    public mutating func handle(_ event: Event) -> Action? {
        switch (state, event) {
        case (.idle, .keyDown(let time)):
            state = .down(since: time)
            return .start
        case (.down(let since), .keyUp(let time)):
            if time - since < Self.holdThreshold {
                state = .latched
                return nil
            }
            state = .idle
            return .stop
        case (.down, .otherKey):
            state = .awaitingRelease
            return .cancel
        case (.latched, .keyDown):
            state = .awaitingRelease
            return .stop
        case (.awaitingRelease, .keyUp):
            state = .idle
            return nil
        default:
            return nil
        }
    }

    /// Forgets any recording in progress, for example after the recorder failed to start.
    public mutating func reset() {
        state = .idle
    }
}
