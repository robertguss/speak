@preconcurrency import AVFoundation
import Foundation

public struct RecordedClip: Sendable {
    public let url: URL
    public let duration: TimeInterval
}

/// Records mono 16 kHz AAC `.m4a` clips from the microphone (KTD9).
///
/// The engine lifetime (`startEngine`/`stopEngine`) owns the input tap and the 16 kHz conversion.
/// The clip lifetime (`beginClip`/`endClip`) only opens and closes the file buffers are written to,
/// so iOS can keep the engine running for a whole session and record many clips (KTD5).
public final class ClipRecorder: @unchecked Sendable {
    public static let clipDirectory = FileManager.default.temporaryDirectory.appending(path: "DictationClips", directoryHint: .isDirectory)
    static let sampleRate: Double = 16_000

    /// Called on the audio thread with the input's RMS level, 0...1.
    public var onLevel: (@Sendable (Float) -> Void)?

    private let engine = AVAudioEngine()
    private let outputFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 1, interleaved: false)!
    private let lock = NSLock()
    private var file: AVAudioFile?
    private var framesWritten: AVAudioFramePosition = 0

    public init() {}

    /// Deletes every clip left behind, for example by a crash mid-request (R15). Call at launch.
    public static func purgeClips() {
        try? FileManager.default.removeItem(at: clipDirectory)
    }

    public func startEngine() throws {
        guard !engine.isRunning else { return }
        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0,
              let converter = AVAudioConverter(from: inputFormat, to: outputFormat) else {
            throw DictationError.microphoneUnavailable(message: "No audio input")
        }
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
            self?.handle(buffer, converter: converter)
        }
        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            throw DictationError.microphoneUnavailable(message: error.localizedDescription)
        }
    }

    public func stopEngine() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
    }

    public func beginClip() throws {
        try FileManager.default.createDirectory(at: Self.clipDirectory, withIntermediateDirectories: true)
        let url = Self.clipDirectory.appending(path: "\(UUID().uuidString).m4a")
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: Self.sampleRate,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: 32_000,
        ]
        let newFile = try AVAudioFile(forWriting: url, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
        lock.withLock {
            file = newFile
            framesWritten = 0
        }
    }

    /// Closes the current clip. Returns `nil` if no clip was open.
    @discardableResult
    public func endClip() -> RecordedClip? {
        let (closing, frames) = lock.withLock {
            defer { file = nil }
            return (file, framesWritten)
        }
        guard let closing else { return nil }
        closing.close()
        return RecordedClip(url: closing.url, duration: Double(frames) / Self.sampleRate)
    }

    /// Ends the current clip and deletes it.
    public func discardClip() {
        if let clip = endClip() {
            try? FileManager.default.removeItem(at: clip.url)
        }
    }

    private func handle(_ buffer: AVAudioPCMBuffer, converter: AVAudioConverter) {
        if let onLevel, let samples = buffer.floatChannelData?[0], buffer.frameLength > 0 {
            var sum: Float = 0
            for i in 0..<Int(buffer.frameLength) { sum += samples[i] * samples[i] }
            onLevel(min(1, sqrt(sum / Float(buffer.frameLength)) * 4))
        }

        lock.lock()
        defer { lock.unlock() }
        guard let file else { return }
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * outputFormat.sampleRate / buffer.format.sampleRate) + 1
        guard let converted = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: capacity) else { return }
        var supplied = false
        var error: NSError?
        converter.convert(to: converted, error: &error) { _, status in
            if supplied {
                status.pointee = .noDataNow
                return nil
            }
            supplied = true
            status.pointee = .haveData
            return buffer
        }
        guard error == nil, converted.frameLength > 0 else { return }
        if (try? file.write(from: converted)) != nil {
            framesWritten += AVAudioFramePosition(converted.frameLength)
        }
    }
}
