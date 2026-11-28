import Foundation

/// Authenticated API client for the per-account main-client-worker.
/// Mirrors `authedFetch` in lib/auth.js: Bearer JWT, one silent renewal on 401.
@MainActor
final class APIClient {
    let auth: AuthManager

    init(auth: AuthManager) { self.auth = auth }

    enum APIError: LocalizedError {
        case notAuthenticated
        case http(Int, String)
        case workerError(String)
        case badResponse
        var errorDescription: String? {
            switch self {
            case .notAuthenticated: return "Session expirée — reconnectez-vous."
            case .http(let code, let msg): return "Erreur \(code) : \(msg)"
            case .workerError(let msg): return msg
            case .badResponse: return "Réponse invalide du serveur."
            }
        }
    }

    // MARK: - Core request

    /// Returns the decoded `resp` payload (the worker wraps everything in {resp}).
    @discardableResult
    func call(_ path: String, method: String = "POST", body: [String: Any]? = nil,
              extraHeaders: [String: String] = [:]) async throws -> Any? {
        guard let base = auth.workerBase else { throw APIError.notAuthenticated }
        // The web workspace owns session renewal — read its freshest JWT.
        // Fall back to the native session only when no web view exists.
        let viaWeb = SessionBridge.shared.webView != nil
        guard let token = viaWeb
                ? await SessionBridge.shared.token(workerBase: base)
                : auth.jwt else {
            throw APIError.notAuthenticated
        }
        var request = try makeRequest(base: base, path: path, method: method, body: body, token: token, extraHeaders: extraHeaders)
        var (data, response) = try await URLSession.shared.data(for: request)

        if let http = response as? HTTPURLResponse, http.statusCode == 401 {
            // JWT rejected — rotate and retry once.
            let fresh: String? = viaWeb
                ? await SessionBridge.shared.forceRenew(workerBase: base)
                : (await auth.exchange() ? auth.jwt : nil)
            if let fresh {
                request = try makeRequest(base: base, path: path, method: method, body: body, token: fresh, extraHeaders: extraHeaders)
                (data, response) = try await URLSession.shared.data(for: request)
            }
        }

        guard let http = response as? HTTPURLResponse else { throw APIError.badResponse }
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        if http.statusCode >= 400 {
            throw APIError.http(http.statusCode, J.str(json ?? [:], "error"))
        }
        if let resp = json?["resp"] {
            if let err = (resp as? [String: Any]).flatMap({ $0["error"] as? String }), !err.isEmpty {
                throw APIError.workerError(err)
            }
            return resp
        }
        return json
    }

    private func makeRequest(base: URL, path: String, method: String,
                             body: [String: Any]?, token: String,
                             extraHeaders: [String: String]) throws -> URLRequest {
        var req = URLRequest(url: base.appendingPathComponent(path))
        req.httpMethod = method
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        for (k, v) in extraHeaders { req.setValue(v, forHTTPHeaderField: k) }
        if let body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        req.timeoutInterval = 30
        return req
    }

    // MARK: - Typed helpers

    func tasks(_ action: String, _ payload: [String: Any] = [:]) async throws -> [String: Any] {
        J.dict(try await call("api/tasks/\(action)", body: payload)) ?? [:]
    }

    func subjects(_ action: String, _ payload: [String: Any] = [:]) async throws -> [String: Any] {
        J.dict(try await call("api/subjects/\(action)", body: payload)) ?? [:]
    }

    /// GET /api/ed/<sub> — ED worker routes accept filter/new_token headers.
    func ed(_ subpath: String, headers: [String: String] = [:]) async throws -> [String: Any] {
        J.dict(try await call("api/ed/\(subpath)", method: "GET", extraHeaders: headers)) ?? [:]
    }

    func edPost(_ subpath: String, _ payload: [String: Any]) async throws -> [String: Any] {
        J.dict(try await call("api/ed/\(subpath)", body: payload)) ?? [:]
    }

    /// POST /api/learning/<action> — chapters, flashcards, learn sessions.
    func learning(_ action: String, _ payload: [String: Any] = [:]) async throws -> [String: Any] {
        J.dict(try await call("api/learning/\(action)", body: payload)) ?? [:]
    }
}
