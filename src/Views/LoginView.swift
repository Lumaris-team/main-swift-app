import SwiftUI
import WebKit

struct LoginView: View {
    @EnvironmentObject var auth: AuthManager

    @State private var username = ""
    @State private var password = ""
    @State private var busy = false
    @State private var error: String?
    @State private var showTurnstile = false
    @State private var pendingLogin = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Spacer()
                Image(systemName: "moon.stars.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(.cyan)
                Text("Lumaris")
                    .font(.largeTitle.bold())
                Text("Workspace, matières et révisions")
                    .foregroundStyle(.secondary)

                VStack(spacing: 14) {
                    TextField("Identifiant", text: $username)
                        .textContentType(.username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .padding(14)
                        .background(Color(.secondarySystemFill))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    SecureField("Mot de passe", text: $password)
                        .textContentType(.password)
                        .padding(14)
                        .background(Color(.secondarySystemFill))
                        .clipShape(RoundedRectangle(cornerRadius: 12))

                    if let error {
                        Text(error)
                            .font(.footnote)
                            .foregroundStyle(.pink)
                            .multilineTextAlignment(.center)
                    }

                    Button {
                        showTurnstile = true
                    } label: {
                        Text(busy ? "Connexion…" : "Se connecter")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(.cyan)
                            .foregroundStyle(.black)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .disabled(busy || username.trimmingCharacters(in: .whitespaces).isEmpty || password.isEmpty)
                }
                .padding(.horizontal, 32)
                Spacer()
            }
            .background(Color(.systemBackground))
            .sheet(isPresented: $showTurnstile) {
                TurnstileSheet(siteKey: Config.turnstileSiteKey) { token in
                    showTurnstile = false
                    Task { await performLogin(turnstileToken: token) }
                } onCancel: {
                    showTurnstile = false
                }
            }
        }
    }

    private func performLogin(turnstileToken: String) async {
        busy = true
        error = nil
        defer { busy = false }
        do {
            try await auth.login(
                username: username.trimmingCharacters(in: .whitespaces),
                password: password,
                turnstileToken: turnstileToken
            )
        } catch {
            self.error = error.localizedDescription
        }
    }
}

// MARK: - Turnstile (Cloudflare check) via WKWebView

/// Hosts the Turnstile widget and returns the token through a JS bridge —
/// same widget the sign-in page renders.
struct TurnstileSheet: View {
    let siteKey: String
    let onToken: (String) -> Void
    let onCancel: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            TurnstileWebView(siteKey: siteKey, onToken: onToken)
                .ignoresSafeArea(edges: .bottom)
                .navigationTitle("Vérification")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Annuler") { onCancel() }
                    }
                }
        }
        .presentationDetents([.medium])
    }
}

private struct TurnstileWebView: UIViewRepresentable {
    let siteKey: String
    let onToken: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onToken: onToken) }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.userContentController.add(context.coordinator, name: "turnstile")
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        let html = """
        <!doctype html><html><head>
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <script src="https://challenges.cloudflare.com/turnstile/v0/api.js?render=explicit" async defer></script>
        <style>body{margin:0;display:flex;min-height:100vh;align-items:center;justify-content:center;background:transparent}</style>
        </head><body>
        <div id="ts"></div>
        <script>
        function ready(){ turnstile.render('#ts', { sitekey: '\(siteKey)', callback: function(t){ window.webkit.messageHandlers.turnstile.postMessage(t); } }); }
        if (window.turnstile) ready(); else { var i=setInterval(function(){ if(window.turnstile){clearInterval(i);ready();} },100); }
        </script></body></html>
        """
        webView.loadHTMLString(html, baseURL: URL(string: "https://lumaris.fr"))
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKScriptMessageHandler {
        let onToken: (String) -> Void
        init(onToken: @escaping (String) -> Void) { self.onToken = onToken }
        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            if let token = message.body as? String, !token.isEmpty {
                DispatchQueue.main.async { self.onToken(token) }
            }
        }
    }
}
