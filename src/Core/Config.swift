import Foundation

/// Worker endpoints, mirroring `account-runtime.js` on the web:
/// `https://<service>-client-worker.<username>-cloudflare-account.workers.dev`
enum Config {
    static let siteBase = "https://lumaris.fr.eu.org"
    /// Shared key letting the app skip the Turnstile widget at login —
    /// verified server-side against the APP_LOGIN_KEY secret-store secret.
    static let appLoginKey = "30c00ab9828a385e3ba658d6c1584dfb9ebed434a652eebe"

    static func encoded(_ username: String) -> String {
        username.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? username
    }

    static func authWorkerBase(username: String) -> URL {
        URL(string: "https://authentication-client-worker.\(encoded(username))-cloudflare-account.workers.dev")!
    }

    static func mainWorkerBase(username: String) -> URL {
        URL(string: "https://main-client-worker.\(encoded(username))-cloudflare-account.workers.dev")!
    }
}
