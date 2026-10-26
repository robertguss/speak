import Foundation
import Synchronization
import XCTest
@testable import DictationCore

final class StubURLProtocol: URLProtocol {
    struct Captured {
        let request: URLRequest
        let body: Data
    }

    struct Reply {
        var status = 200
        var body = Data()
    }

    private static let state = Mutex<(reply: Reply, captured: Captured?)>((Reply(), nil))

    static func reply(_ reply: Reply) {
        state.withLock { $0 = (reply, nil) }
    }

    static var captured: Captured? { state.withLock { $0.captured } }

    static func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        let body = request.httpBody ?? request.httpBodyStream.map(Self.read) ?? Data()
        let reply = Self.state.withLock { state in
            state.captured = Captured(request: request, body: body)
            return state.reply
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: reply.status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: reply.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    private static func read(_ stream: InputStream) -> Data {
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count > 0 else { break }
            data.append(buffer, count: count)
        }
        return data
    }
}

struct FormPart {
    let disposition: String
    let body: Data
    var value: String { String(decoding: body, as: UTF8.self) }
}

/// Splits a multipart/form-data body into its parts, in order, with their `name`.
func formPartList(_ captured: StubURLProtocol.Captured) throws -> [(name: String, part: FormPart)] {
    let contentType = try XCTUnwrap(captured.request.value(forHTTPHeaderField: "Content-Type"))
    XCTAssertTrue(contentType.hasPrefix("multipart/form-data; boundary="))
    let boundary = Data("--\(contentType.components(separatedBy: "boundary=")[1])".utf8)
    let headerEnd = Data("\r\n\r\n".utf8)
    var parts: [(name: String, part: FormPart)] = []
    var chunks: [Data] = []
    var rest = captured.body[...]
    while let range = rest.range(of: boundary) {
        chunks.append(Data(rest[..<range.lowerBound]))
        rest = rest[range.upperBound...]
    }
    for chunk in chunks.dropFirst() {
        guard let split = chunk.range(of: headerEnd) else { continue }
        let headers = String(decoding: chunk[..<split.lowerBound], as: UTF8.self)
        let body = Data(chunk[split.upperBound...].dropLast(2))
        let disposition = headers.components(separatedBy: "\r\n").first { $0.hasPrefix("Content-Disposition") } ?? ""
        let name = try XCTUnwrap(disposition.components(separatedBy: "name=\"").dropFirst().first?.components(separatedBy: "\"").first)
        parts.append((name, FormPart(disposition: disposition, body: body)))
    }
    XCTAssertTrue(rest.starts(with: Data("--\r\n".utf8)), "multipart body must end with the closing boundary")
    return parts
}

/// The multipart parts keyed by `name`; a repeated name keeps its last part.
func formParts(_ captured: StubURLProtocol.Captured) throws -> [String: FormPart] {
    Dictionary(try formPartList(captured), uniquingKeysWith: { _, last in last })
}

/// Every value sent under a repeated multipart field name.
func formValues(_ captured: StubURLProtocol.Captured, _ name: String) throws -> [String] {
    try formPartList(captured).filter { $0.name == name }.map(\.part.value)
}

final class TranscriberTests: XCTestCase {
    private let audio = Bundle.module.url(forResource: "short", withExtension: "m4a", subdirectory: "Fixtures")!

    private func fixture(_ name: String) throws -> Data {
        try Data(contentsOf: XCTUnwrap(Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "Fixtures")))
    }

    private func config(
        _ provider: TranscriptionProviderID,
        base: String? = nil,
        model: String? = nil,
        key: String = "test-key",
        hints: [String] = []
    ) -> TranscriptionConfig {
        TranscriptionConfig(
            provider: provider,
            baseURL: base.map { URL(string: $0)! } ?? provider.defaultBaseURL,
            model: model ?? provider.defaultModel,
            apiKey: key,
            hints: hints
        )
    }

    private func transcribe(_ config: TranscriptionConfig, status: Int = 200, fixture name: String) async throws -> String {
        StubURLProtocol.reply(.init(status: status, body: try fixture(name)))
        return try await Transcribers.make(config: config, session: StubURLProtocol.session()).transcribe(audioFile: audio)
    }

    private func assertThrows(
        _ expected: DictationError,
        _ config: TranscriptionConfig,
        status: Int,
        fixture name: String,
        line: UInt = #line
    ) async throws {
        do {
            let text = try await transcribe(config, status: status, fixture: name)
            XCTFail("expected \(expected), got \(text)", line: line)
        } catch let error as DictationError {
            XCTAssertEqual(error, expected, line: line)
        }
    }

    private var captured: StubURLProtocol.Captured {
        get throws { try XCTUnwrap(StubURLProtocol.captured) }
    }

    // MARK: OpenAI-compatible

    func testOpenAIPostsMultipartToTranscriptionsWithOrWithoutTrailingSlash() async throws {
        for base in ["https://api.openai.com/v1", "https://api.openai.com/v1/"] {
            let text = try await transcribe(config(.openAICompatible, base: base), fixture: "openai-success.json")
            XCTAssertEqual(text, "Hello from the dictation test.")

            let request = try captured.request
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.url?.absoluteString, "https://api.openai.com/v1/audio/transcriptions")
            XCTAssertEqual(request.timeoutInterval, 60)
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-key")

            let parts = try formParts(captured)
            let file = try XCTUnwrap(parts["file"])
            XCTAssertTrue(file.disposition.contains("filename=\"") && file.disposition.contains(".m4a\""), file.disposition)
            XCTAssertEqual(file.body, try Data(contentsOf: audio))
            XCTAssertEqual(parts["model"]?.value, "gpt-transcribe")
        }
    }

    func testOpenAILanguageFieldDependsOnModel() async throws {
        _ = try await transcribe(config(.openAICompatible, model: "gpt-transcribe"), fixture: "openai-success.json")
        var parts = try formParts(captured)
        XCTAssertEqual(parts["languages[]"]?.value, "en")
        XCTAssertNil(parts["language"])

        _ = try await transcribe(config(.openAICompatible, model: "whisper-large-v3-turbo"), fixture: "openai-success.json")
        parts = try formParts(captured)
        XCTAssertEqual(parts["model"]?.value, "whisper-large-v3-turbo")
        XCTAssertEqual(parts["language"]?.value, "en")
        XCTAssertNil(parts["languages[]"])
    }

    func testOpenAIEmptyKeySendsNoAuthorizationHeader() async throws {
        _ = try await transcribe(
            config(.openAICompatible, base: "http://localhost:8000/v1", key: ""),
            fixture: "openai-success.json"
        )
        XCTAssertEqual(try captured.request.url?.absoluteString, "http://localhost:8000/v1/audio/transcriptions")
        XCTAssertNil(try captured.request.value(forHTTPHeaderField: "Authorization"))
    }

    func testOpenAIInsufficientQuotaIsOutOfCredits() async throws {
        try await assertThrows(
            .outOfCredits(message: "You exceeded your current quota, please check your plan and billing details."),
            config(.openAICompatible), status: 429, fixture: "openai-429-insufficient-quota.json"
        )
    }

    func testOpenAIRateLimitIsRateLimited() async throws {
        try await assertThrows(
            .rateLimited(message: "Rate limit reached for requests. Please try again in 20s."),
            config(.openAICompatible), status: 429, fixture: "openai-429-rate-limit.json"
        )
    }

    func testWhitespaceTranscriptIsNoSpeech() async throws {
        try await assertThrows(.noSpeech, config(.openAICompatible), status: 200, fixture: "openai-whitespace.json")
    }

    func testNonJSONBadGatewayIsProviderError() async throws {
        try await assertThrows(
            .provider(status: 502, message: nil),
            config(.openAICompatible), status: 502, fixture: "bad-gateway.html"
        )
    }

    // MARK: Deepgram

    func testDeepgramSendsRawAudioWithQueryAndTokenAuth() async throws {
        let text = try await transcribe(config(.deepgram, key: "dg-key"), fixture: "deepgram-success.json")
        XCTAssertEqual(text, "Hello from the dictation test.")

        let request = try captured.request
        XCTAssertEqual(request.httpMethod, "POST")
        let components = try XCTUnwrap(URLComponents(url: XCTUnwrap(request.url), resolvingAgainstBaseURL: false))
        XCTAssertEqual(components.host, "api.deepgram.com")
        XCTAssertEqual(components.path, "/v1/listen")
        XCTAssertEqual(Set(components.queryItems ?? []), [
            URLQueryItem(name: "model", value: "nova-3"),
            URLQueryItem(name: "smart_format", value: "true"),
            URLQueryItem(name: "language", value: "en"),
        ])
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Token dg-key")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "audio/mp4")
        XCTAssertEqual(try captured.body, try Data(contentsOf: audio))
    }

    func testDeepgramSendsCustomModel() async throws {
        _ = try await transcribe(config(.deepgram, model: "nova-2-general"), fixture: "deepgram-success.json")
        let components = try XCTUnwrap(URLComponents(url: XCTUnwrap(captured.request.url), resolvingAgainstBaseURL: false))
        XCTAssertEqual(components.queryItems?.first { $0.name == "model" }?.value, "nova-2-general")
    }

    func testDeepgramPaymentRequiredIsOutOfCredits() async throws {
        try await assertThrows(
            .outOfCredits(message: "Project does not have enough credits for an ASR request."),
            config(.deepgram), status: 402, fixture: "deepgram-402.json"
        )
    }

    // MARK: ElevenLabs

    func testElevenLabsSendsMultipartWithKeyHeader() async throws {
        let text = try await transcribe(config(.elevenLabs, key: "xi-key"), fixture: "elevenlabs-success.json")
        XCTAssertEqual(text, "Hello from the dictation test.")

        let request = try captured.request
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.absoluteString, "https://api.elevenlabs.io/v1/speech-to-text")
        XCTAssertEqual(request.value(forHTTPHeaderField: "xi-api-key"), "xi-key")

        let parts = try formParts(captured)
        XCTAssertTrue(try XCTUnwrap(parts["file"]).disposition.contains(".m4a\""))
        XCTAssertEqual(parts["model_id"]?.value, "scribe_v2")
        XCTAssertEqual(parts["language_code"]?.value, "en")
        XCTAssertEqual(parts["tag_audio_events"]?.value, "false")
    }

    func testElevenLabsQuotaExceededIsOutOfCredits() async throws {
        try await assertThrows(
            .outOfCredits(message: "This request exceeds your quota of 10000. You have 12 credits remaining, while 40 credits are required for this request."),
            config(.elevenLabs), status: 401, fixture: "elevenlabs-401-quota.json"
        )
    }

    func testElevenLabsInvalidKeyIsInvalidKey() async throws {
        try await assertThrows(
            .invalidKey(message: "Invalid API key"),
            config(.elevenLabs), status: 401, fixture: "elevenlabs-401-invalid-key.json"
        )
    }

    // MARK: Dictionary hints

    func testNoHintsLeaveEveryRequestWithoutHintFields() async throws {
        _ = try await transcribe(config(.openAICompatible), fixture: "openai-success.json")
        XCTAssertEqual(Set(try formPartList(captured).map(\.name)), ["file", "model", "languages[]"])
        _ = try await transcribe(config(.openAICompatible, model: "whisper-large-v3-turbo"), fixture: "openai-success.json")
        XCTAssertEqual(Set(try formPartList(captured).map(\.name)), ["file", "model", "language"])
        _ = try await transcribe(config(.elevenLabs), fixture: "elevenlabs-success.json")
        XCTAssertEqual(Set(try formPartList(captured).map(\.name)), ["file", "model_id", "language_code", "tag_audio_events"])
        _ = try await transcribe(config(.deepgram), fixture: "deepgram-success.json")
        XCTAssertFalse(try XCTUnwrap(captured.request.url?.query).contains("keyterm"))
    }

    func testGPTTranscribeSendsKeywordsAndWhisperSendsAPrompt() async throws {
        _ = try await transcribe(config(.openAICompatible, hints: ["Kubernetes", "PR"]), fixture: "openai-success.json")
        XCTAssertEqual(try formValues(captured, "keywords[]"), ["Kubernetes", "PR"])
        XCTAssertNil(try formParts(captured)["prompt"])

        _ = try await transcribe(config(.openAICompatible, model: "whisper-large-v3-turbo", hints: ["Kubernetes", "PR"]), fixture: "openai-success.json")
        XCTAssertEqual(try formParts(captured)["prompt"]?.value, "Vocabulary: Kubernetes, PR.")
        XCTAssertEqual(try formValues(captured, "keywords[]"), [])
    }

    func testDeepgramSendsEachKeytermStrictlyEncoded() async throws {
        _ = try await transcribe(config(.deepgram, hints: ["pull request", "C++", "R&D", "Zoë"]), fixture: "deepgram-success.json")
        let query = try XCTUnwrap(captured.request.url?.query(percentEncoded: true))
        XCTAssertTrue(query.contains("keyterm=pull%20request"), query)
        XCTAssertTrue(query.contains("keyterm=C%2B%2B"), query)
        XCTAssertTrue(query.contains("keyterm=R%26D"), query)
        XCTAssertTrue(query.contains("keyterm=Zo%C3%AB"), query)
        XCTAssertTrue(query.contains("model=nova-3"), query)
    }

    func testElevenLabsSendsRepeatedKeyterms() async throws {
        _ = try await transcribe(config(.elevenLabs, hints: ["Populi", "kubectl"]), fixture: "elevenlabs-success.json")
        XCTAssertEqual(try formValues(captured, "keyterms"), ["Populi", "kubectl"])
    }
}
