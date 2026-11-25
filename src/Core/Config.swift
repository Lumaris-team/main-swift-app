import Foundation

/// Worker endpoints, mirroring `account-runtime.js` on the web:
/// `https://<service>-client-worker.<username>-cloudflare-account.workers.dev`
enum Config {
    static let turnstileSiteKey = "0x4AAAAAAGBRuixsOkHxqB2N"

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
