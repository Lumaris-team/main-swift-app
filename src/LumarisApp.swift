import SwiftUI

@main
struct LumarisApp: App {
    @StateObject private var auth = AuthManager()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(auth)
                .preferredColorScheme(.dark)
                .tint(Color(red: 0.55, green: 0.92, blue: 1.0))
        }
    }
}
