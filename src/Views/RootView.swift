import SwiftUI

struct RootView: View {
    @EnvironmentObject var auth: AuthManager

    var body: some View {
        Group {
            if auth.isAuthenticated {
                WorkspaceTabs()
            } else {
                LoginView()
            }
        }
    }
}

/// Workspace tabs — the data store is created once, bound to the live session.
struct WorkspaceTabs: View {
    @EnvironmentObject var auth: AuthManager
    @State private var store: WorkspaceStore?
    @State private var tab = 0

    var body: some View {
        Group {
            if let store {
                TabView(selection: $tab) {
                    TasksView(store: store)
                        .tabItem { Label("Tâches", systemImage: "checklist") }
                        .tag(0)
                    SubjectsView(store: store)
                        .tabItem { Label("Matières", systemImage: "book.closed") }
                        .tag(1)
                    TimetableView(store: store)
                        .tabItem { Label("Planning", systemImage: "calendar") }
                        .tag(2)
                }
                .tint(store.theme.accent)
                .font(store.theme.font)
                .background { store.theme.backgroundView() }
                .preferredColorScheme(.dark)
                .task {
                    await store.loadAll()
                    // Force a fresh widget snapshot on every app launch.
                    Task { await WidgetSync.refresh(store: store, force: true) }
                }
            } else {
                ProgressView()
                    .task {
                        store = WorkspaceStore(api: APIClient(auth: auth))
                    }
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button(role: .destructive) {
                        auth.signOut()
                    } label: {
                        Label("Se déconnecter", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                } label: {
                    Image(systemName: "person.crop.circle")
                }
            }
        }
    }
}
