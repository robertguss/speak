import AppKit
@testable import DictationCore
import XCTest
@testable import Dictation

@MainActor
final class TextInserterTests: XCTestCase {
    private var pasteboard: NSPasteboard!

    override func setUp() async throws {
        pasteboard = NSPasteboard(name: .init("DictationTests-\(UUID().uuidString)"))
    }

    override func tearDown() async throws {
        pasteboard.releaseGlobally()
    }

    private func inserter(trusted: Bool = true, onPaste: @escaping @Sendable () -> Void = {}) -> TextInserter {
        TextInserter(pasteboardName: pasteboard.name, restoreDelay: .milliseconds(50), isTrusted: { trusted }, postPaste: onPaste)
    }

    func testImageAndStringAreRestoredAfterInsertion() async {
        let image = Data([0x89, 0x50, 0x4E, 0x47, 1, 2, 3])
        pasteboard.clearContents()
        let item = NSPasteboardItem()
        item.setString("previous", forType: .string)
        item.setData(image, forType: .png)
        pasteboard.writeObjects([item])

        let name = pasteboard.name
        let seen = LockedString()
        let outcome = await inserter { seen.value = NSPasteboard(name: name).string(forType: .string) }.insert("dictated")

        XCTAssertEqual(outcome, .pasted)
        XCTAssertEqual(seen.value, "dictated")
        XCTAssertEqual(pasteboard.string(forType: .string), "previous")
        XCTAssertEqual(pasteboard.data(forType: .png), image)
    }

    func testSnapshotIsNotRestoredWhenUserCopiedDuringDelay() async {
        pasteboard.clearContents()
        pasteboard.setString("previous", forType: .string)
        let name = pasteboard.name

        _ = await inserter {
            DispatchQueue.main.async {
                let board = NSPasteboard(name: name)
                board.clearContents()
                board.setString("copied meanwhile", forType: .string)
            }
        }.insert("dictated")

        XCTAssertEqual(pasteboard.string(forType: .string), "copied meanwhile")
    }

    func testWithoutAccessibilityTextStaysOnClipboard() async {
        pasteboard.clearContents()
        pasteboard.setString("previous", forType: .string)
        let pasted = LockedString()

        let outcome = await inserter(trusted: false) { pasted.value = "posted" }.insert("dictated")
        try? await Task.sleep(for: .milliseconds(100))

        XCTAssertEqual(outcome, .copiedNeedsPaste)
        XCTAssertNil(pasted.value)
        XCTAssertEqual(pasteboard.string(forType: .string), "dictated")
    }

    func testTranscriptionErrorLeavesClipboardUntouched() async throws {
        pasteboard.clearContents()
        pasteboard.setString("previous", forType: .string)
        let before = pasteboard.changeCount

        let settings = SettingsStore(preferences: EmptyBlobStore(), secrets: SecretStore(blob: EmptyBlobStore()))
        let pipeline = DictationPipeline(settings: settings) { _ in FailingTranscriber() }
        let controller = MacDictationController(settings: settings, pipeline: pipeline, inserter: inserter())
        let clip = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).m4a")
        try Data([1]).write(to: clip)

        await controller.process(RecordedClip(url: clip, duration: 2))

        XCTAssertEqual(pasteboard.changeCount, before)
        XCTAssertEqual(pasteboard.string(forType: .string), "previous")
        XCTAssertEqual(controller.lastError, DictationError.invalidKey(message: "bad key").userMessage)
    }
}

private final class LockedString: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: String?
    var value: String? {
        get { lock.withLock { stored } }
        set { lock.withLock { stored = newValue } }
    }
}

private struct EmptyBlobStore: BlobStore {
    func read() throws -> Data? { nil }
    func write(_ data: Data) throws {}
}

private struct FailingTranscriber: Transcriber {
    func transcribe(audioFile: URL) async throws -> String {
        throw DictationError.invalidKey(message: "bad key")
    }
}
