import Foundation

enum TranscriptionHTTP {
    static let timeout: TimeInterval = 60

    static func request(url: URL) -> URLRequest {
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.httpMethod = "POST"
        return request
    }

    static func send(_ request: URLRequest, session: URLSession) async throws -> [String: Any] {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError {
            throw DictationError.network(message: error.localizedDescription)
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        guard (200..<300).contains(status) else {
            throw error(status: status, json: json ?? [:])
        }
        guard let json else {
            throw DictationError.provider(status: status, message: "Unreadable response")
        }
        return json
    }

    static func transcript(_ value: Any?) throws -> String {
        let text = (value as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw DictationError.noSpeech }
        return text
    }

    static func error(status: Int, json: [String: Any]) -> DictationError {
        let openAI = json["error"] as? [String: Any]
        let detail = json["detail"] as? [String: Any]
        let message = openAI?["message"] as? String
            ?? json["err_msg"] as? String
            ?? detail?["message"] as? String
            ?? json["detail"] as? String

        let openAICodes = [openAI?["code"], openAI?["type"]].compactMap { $0 as? String }
        let outOfCredits = status == 402
            || (status == 401 && detail?["status"] as? String == "quota_exceeded")
            || (status == 429 && openAICodes.contains("insufficient_quota"))
        if outOfCredits { return .outOfCredits(message: message) }

        switch status {
        case 401, 403: return .invalidKey(message: message)
        case 429: return .rateLimited(message: message)
        case 413: return .tooLarge(message: message)
        default: return .provider(status: status, message: message)
        }
    }
}
