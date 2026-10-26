import AVFoundation
import DictationCore
import Observation
import UIKit

/// Owns the background recording session that the keyboard drives (R7, R8, KTD4–KTD6).
/// The rules live in `FlowSessionPolicy`; this class supplies the timers, audio, and files.
@MainActor
@Observable
final class FlowSessionController {
    private(set) var isActive = false
    /// Why the session couldn't start, shown instead of the swipe-back screen.
    private(set) var startError: String?
    /// Shown on the main screen until the next successful dictation.
    private(set) var lastError: String?

    private let files: FlowFiles
    private let settings: SettingsStore
    private let pipeline: DictationPipeline
    private let recorder = ClipRecorder()
    private var policy: FlowSessionPolicy
    private var bell: DarwinBell?
    private var ticker: Timer?
    private var observers: [NSObjectProtocol] = []

    init(settings: SettingsStore = .keychain()) {
        files = FlowFiles.appGroup()!
        self.settings = settings
        pipeline = DictationPipeline(settings: settings)
        policy = FlowSessionPolicy(state: files.readState(), idleTimeout: 300)
        write()
        bell = DarwinBell(name: DarwinBell.toApp) { [weak self] in
            Task { @MainActor in self?.handleCommand() }
        }
    }

    func start() async {
        guard !isActive else { return }
        guard await AVAudioApplication.requestRecordPermission() else {
            return fail("Microphone access is off — open the Dictation app")
        }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .default, options: [.mixWithOthers, .allowBluetoothA2DP, .defaultToSpeaker])
            try session.setActive(true)
            try recorder.startEngine()
        } catch {
            recorder.stopEngine()
            return fail("Microphone unavailable — open the Dictation app")
        }
        startError = nil
        isActive = true
        policy.idleTimeout = TimeInterval(settings.load().idleTimeoutMinutes * 60)
        policy.sessionStarted(at: Date())
        ticker = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        observeAudioSession()
        write()
        handleCommand()
    }

    /// Ends the session. Audio captured so far is still transcribed and delivered.
    func end() {
        guard isActive else { return }
        if let id = policy.endSession() {
            finish(id, clip: recorder.endClip())
        }
        recorder.discardClip()
        recorder.stopEngine()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        ticker?.invalidate()
        ticker = nil
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
        isActive = false
        write()
    }

    private func fail(_ message: String) {
        startError = message
        policy.sessionFailed(message)
        write()
    }

    private func tick() {
        let now = Date()
        if policy.idleExpired(at: now) { return end() }
        policy.beat(at: now)
        handleCommand()
    }

    /// Re-reads `command.json`; called on every doorbell and every heartbeat, since doorbells can be lost.
    private func handleCommand() {
        let effect = policy.handle(files.readCommand(), at: Date())
        write()
        switch effect {
        case .beginClip:
            do {
                try recorder.beginClip()
            } catch {
                if let id = policy.state.activeRequestID {
                    policy.finish(id, error: DictationError.microphoneUnavailable(message: error.localizedDescription).userMessage, at: Date())
                    write()
                }
            }
        case .finishClip(let id):
            finish(id, clip: recorder.endClip())
        case .discardClip:
            recorder.discardClip()
        case nil:
            break
        }
    }

    /// Runs the pipeline under a background task, so the request completes even if
    /// the audio that keeps the app alive stops.
    private func finish(_ id: UUID, clip: RecordedClip?) {
        guard let clip else {
            policy.finish(id, error: "Recording failed", at: Date())
            return write()
        }
        var task = UIBackgroundTaskIdentifier.invalid
        task = UIApplication.shared.beginBackgroundTask(withName: "Transcribe") { [weak self] in
            MainActor.assumeIsolated {
                self?.complete(id, error: DictationError.network(message: "Ran out of background time").userMessage)
                UIApplication.shared.endBackgroundTask(task)
            }
        }
        Task {
            do {
                let result = try await pipeline.run(clip: clip.url, duration: clip.duration)
                lastError = nil
                complete(id, text: result.text, cleanupSkipped: result.cleanupSkipped)
            } catch DictationError.tooShort {
                complete(id)
            } catch {
                let message = (error as? DictationError)?.userMessage ?? error.localizedDescription
                lastError = message
                complete(id, error: message)
            }
            UIApplication.shared.endBackgroundTask(task)
        }
    }

    private func complete(_ id: UUID, text: String? = nil, error: String? = nil, cleanupSkipped: Bool = false) {
        policy.finish(id, text: text, error: error, cleanupSkipped: cleanupSkipped, at: Date())
        write()
    }

    private func write() {
        try? files.write(policy.state)
        DarwinBell.ring(DarwinBell.toKeyboard)
    }

    private func observeAudioSession() {
        let center = NotificationCenter.default
        observers = [
            center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] note in
                let began = (note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt) == AVAudioSession.InterruptionType.began.rawValue
                MainActor.assumeIsolated { if began { self?.end() } }
            },
            center.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] note in
                let reason = (note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt).flatMap(AVAudioSession.RouteChangeReason.init)
                MainActor.assumeIsolated {
                    if reason == .oldDeviceUnavailable || reason == .newDeviceAvailable { self?.end() }
                }
            },
            center.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.end() }
            },
        ]
    }
}
