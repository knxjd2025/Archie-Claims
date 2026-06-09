import Foundation

/// Streams responses from the Anthropic Messages API (Claude Opus 4.8) over
/// raw HTTPS + Server-Sent Events. There is no official Swift SDK, so this
/// talks to `POST /v1/messages` directly.
///
/// The user supplies their own Anthropic API key (stored in the Keychain).
/// Teams running a backend proxy can point `baseURL` at it from Settings.
struct ClaudeService {

    static let defaultModel = "claude-opus-4-8"
    static let defaultBaseURL = URL(string: "https://api.anthropic.com")!

    enum ClaudeError: LocalizedError {
        case missingAPIKey
        case http(status: Int, message: String)
        case apiError(type: String, message: String)

        var errorDescription: String? {
            switch self {
            case .missingAPIKey:
                return "No API key set. Add your Anthropic API key in Settings → AI Assistant."
            case .http(let status, let message):
                if status == 401 { return "The API rejected your key (401). Double-check it in Settings." }
                if status == 429 { return "Rate limited by the API (429). Wait a moment and try again." }
                return "API request failed (\(status)). \(message)"
            case .apiError(let type, let message):
                return "\(type): \(message)"
            }
        }
    }

    /// The system prompt that turns Claude into a roofing storm-claim assistant.
    static let systemPrompt = """
    You are Archie, an assistant for residential roofing contractors and door-to-door storm canvassers. \
    You help with: explaining hail/wind roof damage and how to document it (photo checklists, test squares, \
    slope-by-slope notes), drafting homeowner-friendly explanations of the insurance claim process \
    (inspection, ACV vs RCV, deductibles, depreciation, supplements), drafting professional messages \
    (door scripts, follow-up texts, appointment confirmations, claim summary notes for adjusters), and \
    preparing scope/supplement talking points using industry-standard line items.

    Rules:
    - Be practical and concise. Format for a phone screen: short paragraphs, tight bullet lists.
    - Never invent storm dates, hail sizes, or claim outcomes. If property storm context is provided in a \
    <property_context> block, you may reference it; otherwise ask for specifics.
    - You are not a lawyer, insurance adjuster, or public adjuster. For coverage decisions, policy \
    interpretation, or legal questions, say so briefly and recommend the homeowner contact their carrier, \
    a licensed public adjuster, or an attorney. Insurance rules vary by state.
    - Never suggest misrepresenting damage, inflating claims, waiving deductibles where prohibited, or \
    pressuring homeowners. Remind users to follow local solicitation rules and do-not-knock lists when relevant.
    - When asked for a document (script, letter, summary), output it ready to copy, with placeholders in \
    [BRACKETS] for unknowns.
    """

    var apiKey: String
    var baseURL: URL
    var model: String

    init(apiKey: String, baseURL: URL = ClaudeService.defaultBaseURL, model: String = ClaudeService.defaultModel) {
        self.apiKey = apiKey
        self.baseURL = baseURL
        self.model = model
    }

    /// Streams assistant text deltas for the given conversation.
    /// `history` must alternate user/assistant and end with the new user turn.
    func streamReply(history: [ChatMessage]) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    guard !apiKey.trimmingCharacters(in: .whitespaces).isEmpty else {
                        throw ClaudeError.missingAPIKey
                    }
                    let request = try makeRequest(history: history)
                    let (bytes, response) = try await URLSession.shared.bytes(for: request)

                    if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                        var body = ""
                        for try await line in bytes.lines {
                            body += line
                            if body.count > 4000 { break }
                        }
                        throw ClaudeError.http(status: http.statusCode, message: Self.extractErrorMessage(from: body))
                    }

                    for try await line in bytes.lines {
                        guard line.hasPrefix("data: ") else { continue }
                        let payload = String(line.dropFirst(6))
                        guard payload != "[DONE]" else { break }
                        guard let data = payload.data(using: .utf8),
                              let event = try? JSONDecoder().decode(StreamEvent.self, from: data) else { continue }

                        switch event.type {
                        case "content_block_delta":
                            if event.delta?.type == "text_delta", let text = event.delta?.text {
                                continuation.yield(text)
                            }
                        case "error":
                            throw ClaudeError.apiError(
                                type: event.error?.type ?? "api_error",
                                message: event.error?.message ?? "Unknown API error"
                            )
                        case "message_stop":
                            continuation.finish()
                            return
                        default:
                            break
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: - Request building

    private func makeRequest(history: [ChatMessage]) throws -> URLRequest {
        let url = baseURL.appendingPathComponent("v1/messages")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 300
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

        let messages: [[String: Any]] = history.map {
            ["role": $0.role.rawValue, "content": $0.text]
        }

        // Static system prompt with a cache breakpoint: long chats reuse the
        // cached prefix instead of re-billing it every turn.
        let body: [String: Any] = [
            "model": model,
            "max_tokens": 16000,
            "stream": true,
            "thinking": ["type": "adaptive"],
            "system": [
                [
                    "type": "text",
                    "text": Self.systemPrompt,
                    "cache_control": ["type": "ephemeral"]
                ]
            ],
            "messages": messages
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    private static func extractErrorMessage(from body: String) -> String {
        guard let data = body.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let error = object["error"] as? [String: Any],
              let message = error["message"] as? String else {
            return body.isEmpty ? "No details provided." : String(body.prefix(300))
        }
        return message
    }

    // MARK: - SSE event decoding

    private struct StreamEvent: Decodable {
        struct Delta: Decodable {
            let type: String?
            let text: String?
        }
        struct APIError: Decodable {
            let type: String?
            let message: String?
        }
        let type: String
        let delta: Delta?
        let error: APIError?
    }
}
