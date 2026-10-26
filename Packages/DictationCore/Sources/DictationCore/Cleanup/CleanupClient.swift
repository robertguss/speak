import Foundation

public struct CleanupConfig: Sendable, Equatable {
    public var baseURL: URL
    public var model: String
    public var apiKey: String
    public var prompt: String
    /// Preferred spellings from the dictionary (R6, KTD6); empty sends no extra message.
    public var glossary: [String]

    public init(baseURL: URL, model: String, apiKey: String, prompt: String, glossary: [String] = []) {
        self.baseURL = baseURL
        self.model = model
        self.apiKey = apiKey
        self.prompt = prompt
        self.glossary = glossary
    }
}

/// Sends a transcript to an OpenAI-compatible chat endpoint for cleanup (R12, KTD11).
public struct CleanupClient: Sendable {
    static let timeout: TimeInterval = 30

    let config: CleanupConfig
    let session: URLSession

    public init(config: CleanupConfig, session: URLSession = .shared) {
        self.config = config
        self.session = session
    }

    /// Returns the model's cleaned text, unguarded. Throws on any request or parse failure.
    public func clean(_ transcript: String) async throws -> String {
        let tag = "transcript-\(UUID().uuidString.prefix(8).lowercased())"
        var messages = [["role": "system", "content": config.prompt]]
        if !config.glossary.isEmpty {
            // A separate message, so the user's editable prompt stays untouched.
            messages.append(["role": "system", "content": "Preferred spellings. When the transcript contains one of these terms, write it exactly as shown: \(config.glossary.joined(separator: ", "))"])
        }
        messages.append(["role": "user", "content": "<\(tag)>\n\(transcript)\n</\(tag)>"])
        let body: [String: Any] = ["model": config.model, "messages": messages]
        var request = URLRequest(url: config.baseURL.appending(path: "chat").appending(path: "completions"), timeoutInterval: Self.timeout)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !config.apiKey.isEmpty {
            request.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        guard let status = (response as? HTTPURLResponse)?.statusCode, (200..<300).contains(status) else {
            throw DictationError.provider(status: (response as? HTTPURLResponse)?.statusCode ?? 0, message: "Cleanup failed")
        }
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let message = ((json?["choices"] as? [[String: Any]])?.first?["message"]) as? [String: Any]
        guard let content = message?["content"] as? String else {
            throw DictationError.provider(status: status, message: "Unreadable cleanup response")
        }
        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
