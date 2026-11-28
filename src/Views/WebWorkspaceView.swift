import SwiftUI
import WebKit

/// Full Lumaris workspace in a web view — every web feature (chapters, course
/// generation, SM-2 flashcards, learn sessions, gaps, attachments, pomodoro,
/// settings…) works here natively on iOS. Auth tokens are seeded into web
/// storage before page scripts run; the page then owns session renewal.
struct WebWorkspaceView: View {
    @EnvironmentObject var auth: AuthManager

    var body: some View {
        WorkspaceWebView(auth: auth)
            .ignoresSafeArea(edges: .bottom)
    }
}

private struct WorkspaceWebView: UIViewRepresentable {
    let auth: AuthManager

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []

        // Seed auth storage at document start — ONLY for a fresh login
        // (seedId marker). On reloads the page's own renewed tokens are kept.
        if let username = auth.username, let jwt = auth.jwt,
           let ott = auth.oneTimeToken, let seedId = auth.seedId {
            let exp = String(Int(auth.jwtExp.timeIntervalSince1970))
            let seed = """
            (function(){
              var M='lumaris_seed_v';
              if(localStorage.getItem(M)===\(jsLiteral(seedId)))return;
              var d={jwt_token:\(jsLiteral(jwt)),jwt_exp:\(jsLiteral(exp)),one_time_token:\(jsLiteral(ott)),username:\(jsLiteral(username))};
              [localStorage,sessionStorage].forEach(function(s){for(var k in d)s.setItem(k,d[k]);});
              localStorage.setItem(M,\(jsLiteral(seedId)));
            })();
            """
            config.userContentController.addUserScript(
                WKUserScript(source: seed, injectionTime: .atDocumentStart, forMainFrameOnly: true)
            )
        }

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        webView.isOpaque = false
        webView.backgroundColor = .black
        webView.scrollView.backgroundColor = .black
        SessionBridge.shared.webView = webView

        if let url = workspaceURL {
            webView.load(URLRequest(url: url))
        }
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    static func dismantleUIView(_ uiView: WKWebView, coordinator: Coordinator) {
        SessionBridge.shared.webView = nil
    }

    private var workspaceURL: URL? {
        guard let username = auth.username else { return nil }
        return URL(string: "\(Config.siteBase)/account/\(Config.encoded(username))/pages/workspace/")
    }

    private func jsLiteral(_ s: String) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: [s]),
              let str = String(data: data, encoding: .utf8) else { return "\"\"" }
        return String(str.dropFirst().dropLast())
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        // target=_blank links open in Safari instead of a dead web view.
        func webView(_ webView: WKWebView,
                     createWebViewWith configuration: WKWebViewConfiguration,
                     for navigationAction: WKNavigationAction,
                     windowFeatures: WKWindowFeatures) -> WKWebView? {
            if let url = navigationAction.request.url {
                UIApplication.shared.open(url)
            }
            return nil
        }

        // Voice/photo lesson import needs camera + mic inside the page.
        func webView(_ webView: WKWebView,
                     requestMediaCapturePermissionFor origin: WKSecurityOrigin,
                     initiatedByFrame frame: WKFrameInfo,
                     type: WKMediaCaptureType,
                     decisionHandler: @escaping (WKPermissionDecision) -> Void) {
            decisionHandler(.grant)
        }
    }
}
