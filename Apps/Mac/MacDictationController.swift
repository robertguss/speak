import AppKit
import DictationCore
import Observation

@MainActor
@Observable
final class MacDictationController {
    enum Phase: Equatable {
        case idle
        case recording
        case transcribing
        case message(String, isError: Bool)
    }

    private(set) var phase = Phase.idle
    private(set) var level: Float = 0
    private(set) var lastError: String?
    private(set) var hotkeyActive = false

    private let recorder = ClipRecorder()
    private let pipeline: DictationPipeline
    private let inserter: TextInserter
    private let settings: SettingsStore
    private var machine = HotkeyStateMachine()
    private var tap: ModifierKeyTap?
    private var messageTask: Task<Void, Never>?

    init(settings: SettingsStore = .keychain(), pipeline: DictationPipeline? = nil, inserter: TextInserter = TextInserter()) {
        self.settings = settings
        self.pipeline = pipeline ?? DictationPipeline(settings: settings)
        self.inserter = inserter
        recorder.onLevel = { [weak self] value in
            Task { @MainActor in self?.level = value }
        }
    }

    func activateHotkey() {
        if tap == nil {
            tap = ModifierKeyTap { [weak self] event in
                Task { @MainActor in self?.handle(event) }
            }
        }
        tap?.setHotkey(settings.load().macHotkey)
        hotkeyActive = tap?.start() ?? false
    }

    func handle(_ event: HotkeyStateMachine.Event) {
        guard let action = machine.handle(event) else { return }
        switch action {
        case .start: startRecording()
        case .stop: stopRecording()
        case .cancel: cancelRecording()
        }
    }

    private func startRecording() {
        guard phase != .transcribing, phase != .recording else { return }
        do {
            try recorder.startEngine()
            try recorder.beginClip()
            messageTask?.cancel()
            level = 0
            phase = .recording
        } catch {
            recorder.stopEngine()
            machine.reset()
            fail((error as? DictationError) ?? .microphoneUnavailable(message: error.localizedDescription))
        }
    }

    private func stopRecording() {
        guard phase == .recording, let clip = recorder.endClip() else { return }
        recorder.stopEngine()
        phase = .transcribing
        Task { await process(clip) }
    }

    private func cancelRecording() {
        guard phase == .recording else { return }
        recorder.discardClip()
        recorder.stopEngine()
        phase = .idle
    }

    func process(_ clip: RecordedClip) async {
        do {
            let result = try await pipeline.run(clip: clip.url, duration: clip.duration)
            lastError = nil
            switch await inserter.insert(result.text) {
            case .copiedNeedsPaste:
                show("Copied, press ⌘V", isError: false, for: .seconds(4))
            case .pasted where result.cleanupSkipped:
                show("Cleanup skipped", isError: false, for: .seconds(2))
            case .pasted:
                phase = .idle
            }
        } catch DictationError.tooShort {
            phase = .idle
        } catch {
            fail((error as? DictationError) ?? .network(message: error.localizedDescription))
        }
    }

    private func fail(_ error: DictationError) {
        lastError = error.userMessage
        show(error.userMessage, isError: true, for: .seconds(4))
    }

    private func show(_ text: String, isError: Bool, for duration: Duration) {
        phase = .message(text, isError: isError)
        messageTask?.cancel()
        messageTask = Task {
            try? await Task.sleep(for: duration)
            guard !Task.isCancelled, case .message = phase else { return }
            phase = .idle
        }
    }
}
