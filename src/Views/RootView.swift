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
                    WebWorkspaceView()
                        .tabItem { Label("Espace", systemImage: "globe") }
                        .tag(0)
                    TasksView(store: store)
                        .tabItem { Label("Tâches", systemImage: "checklist") }
                        .tag(1)
                    SubjectsView(store: store)
                        .tabItem { Label("Matières", systemImage: "book.closed") }
                        .tag(2)
                    TimetableView(api: store.api)
                        .tabItem { Label("Emploi du temps", systemImage: "calendar") }
                        .tag(3)
                }
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
