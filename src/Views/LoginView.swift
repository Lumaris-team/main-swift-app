import SwiftUI

struct LoginView: View {
    @EnvironmentObject var auth: AuthManager

    @State private var username = ""
    @State private var password = ""
    @State private var busy = false
    @State private var error: String?

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
                        Task { await performLogin() }
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
        }
    }

    private func performLogin() async {
        busy = true
        error = nil
        defer { busy = false }
        do {
            try await auth.login(
                username: username.trimmingCharacters(in: .whitespaces),
                password: password
            )
        } catch {
            self.error = error.localizedDescription
        }
    }
}
