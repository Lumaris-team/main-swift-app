import Foundation
import WebKit

/// The embedded web workspace owns the auth session: the page renews its own
/// JWT every ~9 min through the single-use rotating one-time token. Native
/// code reads the freshest token from the web view's storage instead of
/// running a parallel session — two renewers would invalidate each other's
/// one-time token and log the user out.
@MainActor
final class SessionBridge {
    static let shared = SessionBridge()

    weak var webView: WKWebView?

    private init() {}

    // MARK: - Token access

    /// Fresh JWT from web storage; renews through the page when expired.
    /// Returns nil when there is no web view or the session is dead.
    /// Waits briefly for the seed script to run on first launch.
    func token(workerBase: URL) async -> String? {
        guard let wv = webView else { return nil }
        for _ in 0..<20 {
            if let s = await readSession(wv), s.jwt != nil {
                if s.exp > Date().timeIntervalSince1970 + 30 { return s.jwt }
                return await forceRenew(workerBase: workerBase)
            }
            try? await Task.sleep(nanoseconds: 250_000_000)
        }
        return await forceRenew(workerBase: workerBase)
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
            const exp = String(Math.floor(Date.now() / 1000) + 1800);
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
        if renewed != nil { return renewed }
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
    }

    private func readSession(_ wv: WKWebView) async -> StoredSession? {
        let js = "JSON.stringify({jwt: localStorage.getItem('jwt_token'), exp: Number(localStorage.getItem('jwt_exp')||0)})"
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
                    exp: obj["exp"] as? Double ?? 0
                ))
            }
        }
    }
}
