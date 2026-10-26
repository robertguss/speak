import DictationCore
import UIKit

final class KeyboardViewController: UIInputViewController {
    private static let startAckTimeout: TimeInterval = 1
    private static let stopAckTimeout: TimeInterval = 3

    private let keyboard = KeyboardView()
    private let files = FlowFiles.appGroup()
    private var bell: DarwinBell?
    private var poll: Timer?
    private var deleteRepeat: Timer?
    private var transient: (text: String, until: Date)?
    private var watchdogCommand: (kind: FlowCommand.Kind, id: UUID, at: Date)?
    /// The text field each request was started in, so a result never lands in another field.
    private var requestDocument: (id: UUID, document: UUID)?
    private var opensAppOnNextMic = false

    override func viewDidLoad() {
        super.viewDidLoad()
        keyboard.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(keyboard)
        NSLayoutConstraint.activate([
            keyboard.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            keyboard.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            keyboard.topAnchor.constraint(equalTo: view.topAnchor),
            keyboard.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        keyboard.micButton.addTarget(self, action: #selector(micTapped), for: .touchUpInside)
        keyboard.globeButton.addTarget(self, action: #selector(handleInputModeList(from:with:)), for: .allTouchEvents)
        keyboard.spaceButton.addTarget(self, action: #selector(spaceTapped), for: .touchUpInside)
        keyboard.returnButton.addTarget(self, action: #selector(returnTapped), for: .touchUpInside)
        keyboard.deleteButton.addTarget(self, action: #selector(deleteDown), for: .touchDown)
        keyboard.deleteButton.addTarget(self, action: #selector(deleteUp), for: [.touchUpInside, .touchUpOutside, .touchCancel])
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        keyboard.globeButton.isHidden = !(needsInputModeSwitchKey || UIDevice.current.userInterfaceIdiom == .pad)
        keyboard.show(fullAccess: hasFullAccess)
        bell = DarwinBell(name: DarwinBell.toKeyboard) { [weak self] in
            Task { @MainActor in self?.refresh() }
        }
        poll = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        refresh()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        poll?.invalidate()
        bell = nil
        deleteUp()
        abandonPendingRequestOnDismiss()
    }

    // MARK: - Dictation

    private func read() -> (FlowState, FlowCommand)? {
        guard hasFullAccess, let files else { return nil }
        return (files.readState(), files.readCommand())
    }

    @objc private func micTapped() {
        guard let (state, command) = read() else { return }
        let selector = KeyboardResultSelector(state: state, command: command, now: Date())
        if opensAppOnNextMic {
            opensAppOnNextMic = false
            return openApp()
        }
        switch selector.micAction {
        case .openApp: openApp()
        case .start:
            let id = UUID()
            requestDocument = (id, textDocumentProxy.documentIdentifier)
            send(.start, id: id, command)
        case .stop: send(.stop, id: command.requestID!, command)
        case .wait: break
        }
        refresh()
    }

    private func send(_ kind: FlowCommand.Kind, id: UUID, _ command: FlowCommand) {
        var command = command
        let now = Date()
        command.issue(kind, requestID: id, at: now)
        try? files?.write(command)
        DarwinBell.ring(DarwinBell.toApp)
        watchdogCommand = (kind, id, now)
    }

    /// Keyboard extensions can't call `UIApplication.shared`, but the host app's
    /// `UIApplication` is reachable through the responder chain (requires Full Access).
    private func openApp() {
        var responder: UIResponder? = self
        while let current = responder {
            if let app = current as? UIApplication {
                app.open(AppConstants.startSessionURL)
                return
            }
            responder = current.next
        }
        show("Open the Speak app to start a session", for: 4)
    }

    private func abandonPendingRequestOnDismiss() {
        guard let (state, command) = read(), let pending = command.pendingRequestID else { return }
        var updated = command
        if state.phase == .recording, state.activeRequestID == pending {
            updated.issue(.stop, requestID: pending, at: Date())
        }
        updated.abandoned = true
        try? files?.write(updated)
        DarwinBell.ring(DarwinBell.toApp)
        watchdogCommand = nil
    }

    private func refresh() {
        guard let (state, command) = read() else { return }
        let now = Date()
        let selector = KeyboardResultSelector(state: state, command: command, now: now)

        if let (id, outcome) = selector.resolution {
            // Mark the result consumed before acting on it; if that write fails, act on
            // nothing so a later refresh can't insert the same text twice.
            var consumed = command
            consumed.consumedResultID = id
            guard (try? files?.write(consumed)) != nil else {
                show("Couldn't save dictation state", for: 4)
                return render(state, selector: selector, now: now)
            }
            DarwinBell.ring(DarwinBell.toApp)
            watchdogCommand = nil
            let sameField = requestDocument.map { $0.id != id || $0.document == textDocumentProxy.documentIdentifier } ?? true
            switch outcome {
            case .insert where !sameField:
                show("Dictation discarded", for: 4)
            case .insert(let text, let cleanupSkipped):
                textDocumentProxy.insertText(KeyboardResultSelector.textToInsert(text, after: textDocumentProxy.documentContextBeforeInput))
                if cleanupSkipped { show("Cleanup skipped", for: 2) }
            case .error(let message): show(message, for: 4)
            case .discarded: show("Dictation discarded", for: 4)
            case .nothing: break
            }
            let updated = KeyboardResultSelector(state: state, command: consumed, now: now)
            return render(state, selector: updated, now: now)
        }

        checkWatchdog(state, command, now: now)
        render(state, selector: selector, now: now)
    }

    private func checkWatchdog(_ state: FlowState, _ command: FlowCommand, now: Date) {
        guard let watchdogCommand, command.pendingRequestID == watchdogCommand.id else { return }
        let elapsed = now.timeIntervalSince(watchdogCommand.at)
        let stuck = switch watchdogCommand.kind {
        case .start: elapsed > Self.startAckTimeout && state.activeRequestID != watchdogCommand.id
        case .stop, .cancel: elapsed > Self.stopAckTimeout && !(state.activeRequestID == watchdogCommand.id && state.phase != .recording)
        }
        guard stuck else { return }
        var cleared = command
        cleared.consumedResultID = watchdogCommand.id
        try? files?.write(cleared)
        self.watchdogCommand = nil
        opensAppOnNextMic = true
        show("Tap mic to reconnect", for: 4)
    }

    private func render(_ state: FlowState, selector: KeyboardResultSelector, now: Date) {
        let action = opensAppOnNextMic ? .openApp : selector.micAction
        let status: String
        switch action {
        case .openApp:
            keyboard.setMic(.idle)
            status = state.sessionError ?? "Tap the mic to start a session"
        case .start:
            keyboard.setMic(.idle)
            status = "Ready"
        case .stop:
            keyboard.setMic(.recording)
            status = "Listening… tap to stop"
        case .wait:
            keyboard.setMic(.busy)
            status = "Transcribing…"
        }
        if let transient, transient.until > now {
            keyboard.statusLabel.text = transient.text
        } else {
            transient = nil
            keyboard.statusLabel.text = status
        }
    }

    private func show(_ text: String, for seconds: TimeInterval) {
        transient = (text, Date().addingTimeInterval(seconds))
        keyboard.statusLabel.text = text
    }

    // MARK: - Keys

    @objc private func spaceTapped() { textDocumentProxy.insertText(" ") }
    @objc private func returnTapped() { textDocumentProxy.insertText("\n") }

    @objc private func deleteDown() {
        textDocumentProxy.deleteBackward()
        deleteRepeat = Timer.scheduledTimer(withTimeInterval: 0.45, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.deleteRepeat = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { [weak self] _ in
                    MainActor.assumeIsolated { self?.textDocumentProxy.deleteBackward() }
                }
            }
        }
    }

    @objc private func deleteUp() {
        deleteRepeat?.invalidate()
        deleteRepeat = nil
    }
}
