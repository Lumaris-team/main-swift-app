import Foundation
import WebKit

/// The embedded web workspace owns the auth session: the page renews its own
/// JWT (1h lifetime) through the single-use rotating one-time token (30 days).
/// Native code reads the freshest token from the web view's storage instead of
/// running a parallel session — two renewers would invalidate each other's
/// one-time token and log the user out. `onSession` mirrors web-side renewals
/// into the Keychain so a cold start can renew natively if needed.
@MainActor
final class SessionBridge {
    static let shared = SessionBridge()

    weak var webView: WKWebView?

    /// Fired with the freshest (jwt, oneTimeToken, username, exp) whenever the
    /// web storage is read — AuthManager persists it into the Keychain.
    var onSession: ((String, String, String, Date) -> Void)?

    private init() {}

    // MARK: - Token access

    /// Fresh JWT from web storage; renews through the page when expired.
    /// Returns nil when there is no web view or the session is dead.
    /// Waits briefly for the seed script to run on first launch.
    func token(workerBase: URL) async -> String? {
        guard let wv = webView else { return nil }
        for _ in 0..<20 {
            if let s = await readSession(wv), s.jwt != nil {
                if let jwt = s.jwt, let ott = s.ott, let user = s.username {
                    onSession?(jwt, ott, user, Date(timeIntervalSince1970: s.exp))
                }
                if s.exp > Date().timeIntervalSince1970 + 30 { return s.jwt }
                return await forceRenew(workerBase: workerBase)
            }
            try? await Task.sleep(nanoseconds: 250_000_000)
        }
        return await forceRenew(workerBase: workerBase)
    }

    /// Write a session into web storage — used when the native side renewed
    /// first so the page keeps the freshest single-use token.
    func storeSession(jwt: String, oneTimeToken: String, username: String, exp: Date) async {
        guard let wv = webView else { return }
        let expStr = String(Int(exp.timeIntervalSince1970))
        let js = """
        for (const s of [sessionStorage, localStorage]) {
          s.setItem('jwt_token', \(jsLiteral(jwt)));
          s.setItem('jwt_exp', '\(expStr)');
          s.setItem('one_time_token', \(jsLiteral(oneTimeToken)));
          s.setItem('username', \(jsLiteral(username)));
        }
        'ok'
        """
        _ = await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            wv.evaluateJavaScript(js) { _, _ in cont.resume() }
        }
    }

    /// Force a renewal exchange inside the page and return the new JWT.
    @discardableResult
    func forceRenew(workerBase: URL) async -> String? {
        guard let wv = webView else { return nil }
        let base = workerBase.absoluteString
        let js = """
        (async () => {
          const username = localStorage.getItem('username');
          const ott = localStorage.getItem('one_time_token');
          if (!username || !ott) return null;
          try {
            const r = await fetch('\(base)/api/auth/exchange', {
              method: 'POST',
              headers: { 'Content-Type': 'application/json' },
              body: JSON.stringify({ username, oneTimeToken: ott })
            });
            const d = await r.json();
            if (!(d.valid && d.jwt && d.oneTimeToken)) return null;
            // jwt_exp must match the token's real exp claim (1h lifetime).
            let exp = String(Math.floor(Date.now() / 1000) + 3600);
            for (const s of [sessionStorage, localStorage]) {
              s.setItem('jwt_token', d.jwt);
              s.setItem('jwt_exp', exp);
              s.setItem('one_time_token', d.oneTimeToken);
              s.setItem('username', username);
            }
            return d.jwt;
          } catch (e) { return null; }
        })()
        """
        let renewed = await withCheckedContinuation { (cont: CheckedContinuation<String?, Never>) in
            wv.evaluateJavaScript(js) { result, _ in
                cont.resume(returning: result as? String)
            }
        }
        if renewed != nil {
            if let s = await readSession(wv), let jwt = s.jwt, let ott = s.ott, let user = s.username {
                onSession?(jwt, ott, user, Date(timeIntervalSince1970: s.exp))
            }
            return renewed
        }
        return await readSession(wv)?.jwt
    }

    /// Wipe the page's auth storage (sign-out).
    func clear() async {
        guard let wv = webView else { return }
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            wv.evaluateJavaScript("""
            ['jwt_token','jwt_exp','one_time_token','username','lumaris_seed_v']
              .forEach(k => { localStorage.removeItem(k); sessionStorage.removeItem(k); });
            'ok'
            """) { _, _ in cont.resume() }
        }
    }

    // MARK: - Storage read

    private struct StoredSession {
        let jwt: String?
        let exp: Double // epoch seconds, as stored by lib/auth.js
        let ott: String?
        let username: String?
    }

    private func readSession(_ wv: WKWebView) async -> StoredSession? {
        let js = "JSON.stringify({jwt: localStorage.getItem('jwt_token'), exp: Number(localStorage.getItem('jwt_exp')||0), ott: localStorage.getItem('one_time_token'), user: localStorage.getItem('username')})"
        return await withCheckedContinuation { (cont: CheckedContinuation<StoredSession?, Never>) in
            wv.evaluateJavaScript(js) { result, _ in
                guard let str = result as? String,
                      let data = str.data(using: .utf8),
                      let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                else {
                    cont.resume(returning: nil)
                    return
                }
                cont.resume(returning: StoredSession(
                    jwt: obj["jwt"] as? String,
                    exp: obj["exp"] as? Double ?? 0,
                    ott: obj["ott"] as? String,
                    username: obj["user"] as? String
                ))
            }
        }
    }

    private func jsLiteral(_ s: String) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: [s]),
              let str = String(data: data, encoding: .utf8) else { return "\"\"" }
        return String(str.dropFirst().dropLast())
    }
}
