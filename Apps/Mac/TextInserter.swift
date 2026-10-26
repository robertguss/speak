import AppKit
import ApplicationServices

struct TextInserter: Sendable {
    enum Outcome: Equatable {
        case pasted
        case copiedNeedsPaste
    }

    private static let transientType = NSPasteboard.PasteboardType("org.nspasteboard.TransientType")

    var pasteboardName: NSPasteboard.Name = .general
    var restoreDelay: Duration = .milliseconds(1500)
    var isTrusted: @Sendable () -> Bool = { AXIsProcessTrusted() }
    var postPaste: @Sendable () -> Void = Self.postCommandV

    @MainActor
    func insert(_ text: String) async -> Outcome {
        let pasteboard = NSPasteboard(name: pasteboardName)
        let snapshot = (pasteboard.pasteboardItems ?? []).map { item in
            item.types.compactMap { type in item.data(forType: type).map { (type, $0) } }
        }

        pasteboard.clearContents()
        let item = NSPasteboardItem()
        item.setString(text, forType: .string)
        item.setData(Data(), forType: Self.transientType)
        pasteboard.writeObjects([item])
        let written = pasteboard.changeCount

        guard isTrusted() else { return .copiedNeedsPaste }
        postPaste()

        try? await Task.sleep(for: restoreDelay)
        guard pasteboard.changeCount == written else { return .pasted }
        pasteboard.clearContents()
        pasteboard.writeObjects(snapshot.map { entries in
            let restored = NSPasteboardItem()
            for (type, data) in entries { restored.setData(data, forType: type) }
            return restored
        })
        return .pasted
    }

    private static func postCommandV() {
        let source = CGEventSource(stateID: .combinedSessionState)
        let vKey: CGKeyCode = 9
        let down = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: false)
        down?.flags = .maskCommand
        up?.flags = .maskCommand
        down?.post(tap: .cgAnnotatedSessionEventTap)
        up?.post(tap: .cgAnnotatedSessionEventTap)
    }
}
