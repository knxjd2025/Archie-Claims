import Foundation

/// Client for the main Archie (roof-report-ai) backend — the same Express API
/// that powers the Archie web CRM (Render service `roofy-backend`, fronted by
/// app.archie.now). Users sign in with their existing Archie account; the AI
/// chat is served by `POST /api/ai-assistant` (`action: "chat"`), which builds
/// its own roofing-expert system prompt and enriches it with the user's
/// company info from the CRM database.
///
/// Auth: `POST /api/auth/login` sets an httpOnly `roof_report_token` cookie,
/// and the middleware also accepts `Authorization: Bearer <jwt>`. After login
/// we fetch the raw JWT from `GET /api/auth/token` (cookie attached
/// automatically by URLSession) and keep it in the Keychain for Bearer use.
/// Tokens last 7 days; on a 401 we silently re-login once with the stored
/// credentials before surfacing an error.
struct ArchieBackendService {

    /// The main app's domain. Vercel proxies `/api/*` (including Set-Cookie)
    /// to the Render backend, so accounts here are the same as the web app's.
    static let defaultBaseURL = URL(string: "https://app.archie.now")!

    enum BackendError: LocalizedError {
        case notSignedIn
        case invalidCredentials(String)
        case sessionExpired
        case rateLimited
        case http(status: Int, message: String)
        case malformedResponse

        var errorDescription: String? {
            switch self {
            case .notSignedIn:
                return "Sign in with your Archie account in Settings → AI Assistant to use Archie."
            case .invalidCredentials(let message):
                return message.isEmpty ? "Invalid email or password." : message
            case .sessionExpired:
                return "Your Archie session expired. Sign in again in Settings → AI Assistant."
            case .rateLimited:
                return "Archie is rate limited right now. Wait a moment and try again."
            case .http(let status, let message):
                return "Archie backend request failed (\(status)). \(message)"
            case .malformedResponse:
                return "The Archie backend returned an unexpected response."
            }
        }
    }

    var baseURL: URL

    init(baseURL: URL = ArchieBackendService.defaultBaseURL) {
        self.baseURL = baseURL
    }

    // MARK: - Auth

    /// Signs in with an Archie account, stores the JWT + credentials in the
    /// Keychain, and returns the signed-in user's email.
    @discardableResult
    func signIn(email: String, password: String) async throws -> String {
        try await authenticate(path: "api/auth/login", body: [
            "email": email,
            "password": password
        ], email: email, password: password)
    }

    /// Creates a new Archie account (same accounts as app.archie.now; new
    /// accounts start on the free tier) and signs in.
    @discardableResult
    func signUp(name: String, email: String, password: String) async throws -> String {
        try await authenticate(path: "api/auth/signup", body: [
            "name": name,
            "email": email,
            "password": password
        ], email: email, password: password)
    }

    private func authenticate(
        path: String,
        body: [String: String],
        email: String,
        password: String
    ) async throws -> String {
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = "POST"
        request.timeoutInterval = 90
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw BackendError.malformedResponse }

        guard http.statusCode == 200 || http.statusCode == 201 else {
            let message = Self.errorMessage(from: data)
            if [400, 401, 403, 409].contains(http.statusCode) {
                throw BackendError.invalidCredentials(message)
            }
            if http.statusCode == 429 { throw BackendError.rateLimited }
            throw BackendError.http(status: http.statusCode, message: message)
        }

        // The JWT is delivered ONLY in the Set-Cookie header (roof_report_token),
        // never in the JSON body. Extract it directly; GET /api/auth/token is
        // cookie-only, so it serves as a fallback via URLSession's cookie jar.
        let token: String
        if let cookieToken = Self.authToken(fromResponse: http, requestURL: request.url) {
            token = cookieToken
        } else {
            token = try await fetchToken()
        }
        KeychainStore.save(token, account: KeychainStore.archieTokenAccount)
        KeychainStore.save(email, account: KeychainStore.archieEmailAccount)
        KeychainStore.save(password, account: KeychainStore.archiePasswordAccount)
        return email
    }

    /// Clears the stored Archie session and credentials.
    static func signOut() {
        KeychainStore.delete(account: KeychainStore.archieTokenAccount)
        KeychainStore.delete(account: KeychainStore.archieEmailAccount)
        KeychainStore.delete(account: KeychainStore.archiePasswordAccount)
        for host in ["https://app.archie.now", "https://roofy-backend.onrender.com"] {
            if let url = URL(string: host),
               let cookies = HTTPCookieStorage.shared.cookies(for: url) {
                cookies.forEach { HTTPCookieStorage.shared.deleteCookie($0) }
            }
        }
    }

    static var signedInEmail: String? {
        guard KeychainStore.read(account: KeychainStore.archieTokenAccount) != nil else { return nil }
        return KeychainStore.read(account: KeychainStore.archieEmailAccount)
    }

    /// Pulls the `roof_report_token` JWT out of the login response's
    /// Set-Cookie header (or the cookie jar, where URLSession stores it).
    private static func authToken(fromResponse response: HTTPURLResponse, requestURL: URL?) -> String? {
        if let url = requestURL {
            let headers = response.allHeaderFields as? [String: String] ?? [:]
            let cookies = HTTPCookie.cookies(withResponseHeaderFields: headers, for: url)
            if let cookie = cookies.first(where: { $0.name == "roof_report_token" }), !cookie.value.isEmpty {
                return cookie.value
            }
            if let stored = HTTPCookieStorage.shared.cookies(for: url)?
                .first(where: { $0.name == "roof_report_token" }), !stored.value.isEmpty {
                return stored.value
            }
        }
        return nil
    }

    /// `GET /api/auth/token` — returns the raw JWT, but only for cookie
    /// sessions (the route re-reads the cookie, not the Bearer header).
    private func fetchToken() async throws -> String {
        var request = URLRequest(url: baseURL.appendingPathComponent("api/auth/token"))
        request.timeoutInterval = 30
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let token = object["token"] as? String, !token.isEmpty else {
            throw BackendError.malformedResponse
        }
        return token
    }

    /// Re-login with stored credentials (token expired). Returns a fresh JWT.
    private func refreshSession() async throws -> String {
        guard let email = KeychainStore.read(account: KeychainStore.archieEmailAccount),
              let password = KeychainStore.read(account: KeychainStore.archiePasswordAccount),
              !email.isEmpty, !password.isEmpty else {
            throw BackendError.sessionExpired
        }
        do {
            try await signIn(email: email, password: password)
        } catch {
            throw BackendError.sessionExpired
        }
        guard let token = KeychainStore.read(account: KeychainStore.archieTokenAccount) else {
            throw BackendError.sessionExpired
        }
        return token
    }

    // MARK: - Chat

    /// Sends the conversation to the Archie backend and yields the reply.
    /// The endpoint is not streaming, so the full reply arrives as one delta —
    /// the stream interface keeps `AssistantView` agnostic of the backend.
    func streamReply(history: [ChatMessage]) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let reply = try await chat(history: history)
                    continuation.yield(reply)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// `POST /api/ai-assistant` with `action: "chat"`. The last user turn is
    /// sent as `question`; everything before it as `conversation_history`.
    func chat(history: [ChatMessage]) async throws -> String {
        guard var token = KeychainStore.read(account: KeychainStore.archieTokenAccount),
              !token.isEmpty else {
            throw BackendError.notSignedIn
        }

        guard let lastUserTurn = history.last(where: { $0.role == .user }) else {
            throw BackendError.malformedResponse
        }
        let priorTurns = history.prefix(while: { $0.id != lastUserTurn.id })
            .filter { !$0.text.isEmpty }
            .map { ["role": $0.role.rawValue, "content": $0.text] }

        var attempt = 0
        while true {
            attempt += 1
            let (data, status) = try await postChat(
                token: token,
                question: lastUserTurn.text,
                conversationHistory: Array(priorTurns)
            )

            if status == 401, attempt == 1 {
                token = try await refreshSession()
                continue
            }
            if status == 401 { throw BackendError.sessionExpired }
            if status == 429 { throw BackendError.rateLimited }
            guard status == 200 else {
                throw BackendError.http(status: status, message: Self.errorMessage(from: data))
            }

            guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let reply = object["response"] as? String, !reply.isEmpty else {
                throw BackendError.malformedResponse
            }
            return reply
        }
    }

    private func postChat(
        token: String,
        question: String,
        conversationHistory: [[String: String]]
    ) async throws -> (Data, Int) {
        var request = URLRequest(url: baseURL.appendingPathComponent("api/ai-assistant"))
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "action": "chat",
            "question": question,
            "conversation_history": conversationHistory
        ])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw BackendError.malformedResponse }
        return (data, http.statusCode)
    }

    private static func errorMessage(from data: Data) -> String {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return String(data: data.prefix(300), encoding: .utf8) ?? "No details provided."
        }
        return (object["error"] as? String) ?? (object["message"] as? String) ?? "No details provided."
    }
}
