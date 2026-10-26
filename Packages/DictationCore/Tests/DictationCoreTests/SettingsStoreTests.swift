import XCTest
@testable import DictationCore

final class SettingsStoreTests: XCTestCase {
    func testPreferencesRoundTrip() throws {
        var prefs = AppPreferences()
        prefs.transcriptionProvider = .elevenLabs
        prefs.openAICompatibleBaseURL = URL(string: "https://api.groq.com/openai/v1")!
        prefs.deepgramModel = "nova-4"
        prefs.cleanupEnabled = true
        prefs.cleanupPrompt = "Fix punctuation."
        prefs.macHotkey = .fn
        prefs.idleTimeoutMinutes = 15

        let decoded = try JSONDecoder().decode(AppPreferences.self, from: JSONEncoder().encode(prefs))
        XCTAssertEqual(decoded, prefs)
    }

    func testMissingFieldsGetDefaultsAndKeepTheRest() throws {
        let json = #"{"transcriptionProvider":"deepgram","deepgramModel":"nova-3-medical"}"#
        let prefs = try JSONDecoder().decode(AppPreferences.self, from: Data(json.utf8))

        XCTAssertEqual(prefs.transcriptionProvider, .deepgram)
        XCTAssertEqual(prefs.deepgramModel, "nova-3-medical")
        XCTAssertEqual(prefs.elevenLabsModel, "scribe_v2")
        XCTAssertFalse(prefs.cleanupEnabled)
        XCTAssertNil(prefs.cleanupPrompt)
        XCTAssertEqual(prefs.idleTimeoutMinutes, 5)
    }

    func testUnknownProviderFallsBackToDefault() throws {
        let json = #"{"transcriptionProvider":"assemblyAI","elevenLabsModel":"scribe_v3"}"#
        let prefs = try JSONDecoder().decode(AppPreferences.self, from: Data(json.utf8))

        XCTAssertEqual(prefs.transcriptionProvider, .openAICompatible)
        XCTAssertEqual(prefs.elevenLabsModel, "scribe_v3")
    }

    func testEditKeepsUnknownKeysAndWritesOnlyTheEditedField() throws {
        let (store, blob, _) = SettingsStore.inMemory(
            preferencesJSON: #"{"futureField":{"nested":[1,2]},"deepgramModel":"nova-3-medical"}"#
        )

        try store.update { $0.cleanupEnabled = true }

        let stored = blob.jsonObject
        XCTAssertEqual(Set(stored.keys), ["futureField", "deepgramModel", "cleanupEnabled"])
        XCTAssertEqual(stored["futureField"] as? [String: [Int]], ["nested": [1, 2]])
        XCTAssertEqual(stored["deepgramModel"] as? String, "nova-3-medical")
        XCTAssertEqual(stored["cleanupEnabled"] as? Bool, true)
    }

    func testResettingPromptRemovesItFromTheBlob() throws {
        let (store, blob, _) = SettingsStore.inMemory(preferencesJSON: #"{"cleanupPrompt":"Custom"}"#)

        let prefs = try store.update { $0.cleanupPrompt = nil }

        XCTAssertNil(prefs.cleanupPrompt)
        XCTAssertNil(blob.jsonObject["cleanupPrompt"])
    }

    func testLoadingWithNoItemReturnsDefaultsAndWritesNothing() {
        let (store, preferences, secrets) = SettingsStore.inMemory()

        XCTAssertEqual(store.load(), AppPreferences())
        XCTAssertEqual(store.apiKey(.transcription, baseURL: URL(string: "https://api.openai.com/v1")!), "")
        XCTAssertEqual(preferences.writeCount, 0)
        XCTAssertEqual(secrets.writeCount, 0)
    }

    func testKeyIsTiedToHostSoSwitchingBaseURLFindsNoKey() throws {
        let (store, _, _) = SettingsStore.inMemory()
        try store.setAPIKey("sk-openai", role: .transcription, baseURL: URL(string: "https://api.openai.com/v1")!)

        var prefs = try store.update { $0.openAICompatibleBaseURL = URL(string: "https://api.groq.com/openai/v1")! }
        XCTAssertEqual(store.transcriptionConfig(prefs).apiKey, "")

        prefs = try store.update { $0.openAICompatibleBaseURL = URL(string: "https://api.openai.com/v1/")! }
        XCTAssertEqual(store.transcriptionConfig(prefs).apiKey, "sk-openai")
    }

    func testCleanupKeyIsSeparateFromTranscriptionKeyOnSameHost() throws {
        let (store, _, _) = SettingsStore.inMemory()
        let openAI = URL(string: "https://api.openai.com/v1")!
        try store.setAPIKey("sk-transcribe", role: .transcription, baseURL: openAI)

        XCTAssertEqual(store.apiKey(.cleanup, baseURL: openAI), "")
    }

    func testSecretStoreStoresReadsOverwritesAndDeletes() throws {
        let blob = InMemoryBlobStore()
        let secrets = SecretStore(blob: blob)

        try secrets.setValue("one", for: "transcription:api.deepgram.com")
        try secrets.setValue("other", for: "cleanup:api.openai.com")
        XCTAssertEqual(secrets.value(for: "transcription:api.deepgram.com"), "one")

        try secrets.setValue("two", for: "transcription:api.deepgram.com")
        XCTAssertEqual(secrets.value(for: "transcription:api.deepgram.com"), "two")

        try secrets.setValue(nil, for: "transcription:api.deepgram.com")
        XCTAssertNil(secrets.value(for: "transcription:api.deepgram.com"))
        XCTAssertEqual(secrets.value(for: "cleanup:api.openai.com"), "other")
    }

    func testSecretWriteFailsWithoutWritingWhenItemCannotBeRead() {
        let secrets = SecretStore(blob: UnreadableBlobStore())

        XCTAssertThrowsError(try secrets.setValue("sk", for: "transcription:api.openai.com"))
    }

    func testSecretWriteFailsWithoutWritingWhenItemCannotBeDecoded() {
        let blob = InMemoryBlobStore(json: "not json")
        let secrets = SecretStore(blob: blob)

        XCTAssertThrowsError(try secrets.setValue("sk", for: "transcription:api.openai.com"))
        XCTAssertEqual(blob.writeCount, 0)
    }
}

private struct UnreadableBlobStore: BlobStore {
    func read() throws -> Data? { throw KeychainError(status: errSecInteractionNotAllowed) }
    func write(_ data: Data) throws { XCTFail("must not write after a failed read") }
}
