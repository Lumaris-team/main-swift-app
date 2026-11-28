import Foundation
import WidgetKit

/// Session state — mirrors `lib/auth.js`: JWT + one-time token, renewed via
/// `/api/auth/exchange` on the main worker (30 min JWT lifetime).
@MainActor
final class AuthManager: ObservableObject {
    @Published private(set) var username: String?
    @Published private(set) var jwt: String?
    @Published private(set) var jwtExp: Date = .distantPast
    @Published private(set) var isAuthenticated = false

    /// Readable for the web-workspace seed script; the page owns renewals.
    private(set) var oneTimeToken: String?

    /// Per-login marker stored in web storage: tells the seed script whether
    /// it already injected this session's tokens (avoids clobbering the
    /// page's self-renewed credentials on reload).
    private(set) var seedId: String?

    init() {
        restore()
    }

    private func restore() {
        guard let user = Keychain.read("username"),
              let token = Keychain.read("oneTimeToken"),
              let expStr = Keychain.read("jwtExp"),
              let exp = Double(expStr) else { return }
        username = user
        oneTimeToken = token
        seedId = Keychain.read("seedId")
        jwtExp = Date(timeIntervalSince1970: exp)
        jwt = Keychain.read("jwt")
        // JWT may be expired — APIClient will renew lazily on first call.
        isAuthenticated = true
    }

    var workerBase: URL? {
        username.map { Config.mainWorkerBase(username: $0) }
    }

    var isJWTValid: Bool {
        jwt != nil && jwtExp > Date().addingTimeInterval(30)
    }

    // MARK: - Login (authentication-client-worker)

    /// POST /api/login. The worker intentionally never responds on failure —
    /// a timeout surfaces as the generic credentials error, like the web.
    func login(username: String, password: String, turnstileToken: String) async throws {
        let url = Config.authWorkerBase(username: username).appendingPathComponent("api/login")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 15
        req.httpBody = try JSONSerialization.data(withJSONObject: [
            "username": username,
            "password": password,
            "turnstileToken": turnstileToken,
        ])

        let (data, resp): (Data, URLResponse)
        do {
            (data, resp) = try await URLSession.shared.data(for: req)
        } catch {
            throw AuthError.badCredentials
        }
        guard let http = resp as? HTTPURLResponse, http.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let jwt = json["jwt"] as? String,
              let ott = json["oneTimeToken"] as? String else {
            throw AuthError.badCredentials
        }
        self.username = username
        self.jwt = jwt
        self.oneTimeToken = ott
        self.seedId = UUID().uuidString
        persist(jwt: jwt, oneTimeToken: ott, username: username)
        await exchange() // get a fresh JWT + rotated one-time token
        isAuthenticated = true
    }

    // MARK: - Exchange / renewal

    /// POST /api/auth/exchange { username, oneTimeToken } → fresh JWT.
    @discardableResult
    func exchange() async -> Bool {
        guard let base = workerBase, let ott = oneTimeToken, let user = username else { return false }
        var req = URLRequest(url: base.appendingPathComponent("api/auth/exchange"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 15
        req.httpBody = try? JSONSerialization.data(withJSONObject: [
            "username": user,
            "oneTimeToken": ott,
        ])
        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              let http = resp as? HTTPURLResponse, http.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              json["valid"] as? Bool == true,
              let newJWT = json["jwt"] as? String,
              let newOTT = json["oneTimeToken"] as? String else { return false }
        jwt = newJWT
        oneTimeToken = newOTT
        persist(jwt: newJWT, oneTimeToken: newOTT, username: user)
        return true
    }

    func signOut() {
        username = nil
        jwt = nil
        oneTimeToken = nil
        seedId = nil
        isAuthenticated = false
        for key in ["jwt", "oneTimeToken", "username", "jwtExp", "seedId"] {
            Keychain.delete(key)
        }
        // The web workspace keeps its own copy of the session — wipe it too.
        Task { await SessionBridge.shared.clear() }
        WidgetSnapshotStore.clear()
        ShortcutJSONStore.clearAll()
        WidgetCenter.shared.reloadAllTimelines()
    }

    private func persist(jwt: String, oneTimeToken: String, username: String) {
        // JWT exp claim → renewal time (default 30 min like the web).
        var exp: TimeInterval = 1800
        let parts = jwt.split(separator: ".")
        if parts.count >= 2,
           let payload = Data(base64Encoded: padBase64(String(parts[1]))),
           let json = try? JSONSerialization.jsonObject(with: payload) as? [String: Any],
           let e = json["exp"] as? Double {
            exp = e - Date().timeIntervalSince1970
        }
        jwtExp = Date().addingTimeInterval(max(60, exp))
        Keychain.save("jwt", jwt)
        Keychain.save("oneTimeToken", oneTimeToken)
        Keychain.save("username", username)
        Keychain.save("jwtExp", String(jwtExp.timeIntervalSince1970))
        if let seedId { Keychain.save("seedId", seedId) }
    }

    private func padBase64(_ s: String) -> String {
        var t = s.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while t.count % 4 != 0 { t += "=" }
        return t
    }

    enum AuthError: LocalizedError {
        case badCredentials
        var errorDescription: String? { "Identifiant ou mot de passe incorrect." }
    }
}
