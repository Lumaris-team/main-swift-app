import SwiftUI

/// Tasks tab — mirrors the web workspace: segmented filter, search,
/// due-date grouping, swipe to done/trash, detail sheet.
struct TasksView: View {
    @ObservedObject var store: WorkspaceStore
    @State private var filter = 0 // 0 toutes, 1 récurrentes, 2 événements, 3 corbeille
    @State private var query = ""
    @State private var selected: (table: String, row: [String: Any])?
    @State private var editingNew = false

    private let filters = ["Toutes", "Récurrentes", "Événements", "Corbeille"]

    private var rows: [(table: String, row: [String: Any])] {
        let all = store.allRows()
        var out = all.filter { entry in
            let t = entry.table
            switch filter {
            case 1: return t.hasPrefix("repeat")
            case 2: return t == "events" || t == "repeat_events"
            default: return true
            }
        }
        if filter == 3 {
            out = ["trash_tasks", "trash_events"].flatMap { t in
                (store.tables[t] ?? []).map { (t, $0) }
            }
        }
        if !query.isEmpty {
            let q = query.lowercased()
            out = out.filter {
                J.str($0.row, "title").lowercased().contains(q)
                    || J.str($0.row, "text_body").lowercased().contains(q)
            }
        }
        return out.sorted { a, b in
            let da = J.date(a.row, "remind_date") ?? .distantFuture
            let db = J.date(b.row, "remind_date") ?? .distantFuture
            if da != db { return da < db }
            return J.int(a.row, "task_id") > J.int(b.row, "task_id")
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Filtre", selection: $filter) {
                    ForEach(filters.indices, id: \.self) { Text(filters[$0]).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.vertical, 8)

                List {
                    ForEach(rows, id: \.row.taskId) { entry in
                        TaskRow(entry: entry, store: store) {
                            selected = entry
                        }
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            if !entry.table.hasPrefix("trash") {
                                Button {
                                    Task { await store.deleteTask(table: entry.table, taskId: J.int(entry.row, "task_id")) }
                                } label: { Label("Corbeille", systemImage: "trash") }
                                .tint(.orange)
                            } else {
                                Button {
                                    Task {
                                        _ = try? await store.api.tasks("restore", ["table": entry.table, "task_id": J.int(entry.row, "task_id")])
                                        await store.loadAll()
                                    }
                                } label: { Label("Restaurer", systemImage: "arrow.uturn.backward") }
                                .tint(.blue)
                            }
                        }
                        .swipeActions(edge: .leading, allowsFullSwipe: true) {
                            if !entry.table.hasPrefix("trash") {
                                Button {
                                    Task { await store.toggleDone(table: entry.table, taskId: J.int(entry.row, "task_id")) }
                                } label: {
                                    Label(J.bool(entry.row, "is_done") ? "À faire" : "Fait", systemImage: J.bool(entry.row, "is_done") ? "arrow.uturn.backward.circle" : "checkmark.circle")
                                }
                                .tint(.green)
                            }
                        }
                    }
                }
                .listStyle(.plain)
                .searchable(text: $query, prompt: "Rechercher…")
                .overlay {
                    if rows.isEmpty && !store.isLoading {
                        ContentUnavailableView(
                            "Rien ici",
                            systemImage: "tray",
                            description: Text(query.isEmpty ? "Aucune tâche dans cette vue." : "Aucun résultat pour « \(query) ».")
                        )
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(store.theme.background)
            .navigationTitle("Tâches")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { editingNew = true } label: { Image(systemName: "plus") }
                }
            }
            .refreshable { await store.loadAll() }
            .sheet(item: Binding(
                get: { selected.map { IdentifiedRow(id: "\($0.table)-\(J.int($0.row, "task_id"))", entry: $0) } },
                set: { if $0 == nil { selected = nil } }
            )) { item in
                TaskDetailView(store: store, table: item.entry.table, row: item.entry.row) {
                    selected = nil
                }
            }
            .sheet(isPresented: $editingNew) {
                TaskEditorView(store: store, table: "tasks", row: nil) { editingNew = false }
            }
        }
    }
}

private struct IdentifiedRow: Identifiable {
    let id: String
    let entry: (table: String, row: [String: Any])
}

private extension Dictionary where Key == String, Value == Any {
    var taskId: Int { J.int(self, "task_id") }
}

// MARK: - Row

private struct TaskRow: View {
    let entry: (table: String, row: [String: Any])
    @ObservedObject var store: WorkspaceStore
    let onTap: () -> Void

    private var dueBucket: String {
        guard let d = J.date(entry.row, "remind_date") else { return "none" }
        let cal = Calendar.current
        if cal.isDateInToday(d) { return "today" }
        if d < Date() { return "overdue" }
        return "later"
    }

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: J.bool(entry.row, "is_done") ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(J.bool(entry.row, "is_done") ? .green : .secondary)
                    .font(.title3)
                VStack(alignment: .leading, spacing: 4) {
                    Text(J.str(entry.row, "title").isEmpty ? "Sans titre" : J.str(entry.row, "title"))
                        .font(.body.weight(.medium))
                        .strikethrough(J.bool(entry.row, "is_done"))
                        .foregroundStyle(J.bool(entry.row, "is_done") ? .secondary : .primary)
                    HStack(spacing: 8) {
                        if let d = J.date(entry.row, "remind_date") {
                            Label(J.fmtDate(d), systemImage: "calendar")
                                .font(.caption)
                                .foregroundStyle(dueBucket == "overdue" ? .red : .secondary)
                        }
                        if J.int(entry.row, "chapter_id") > 0 {
                            Text(store.chapterName(J.int(entry.row, "chapter_id")))
                                .font(.caption2)
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(store.theme.accent.opacity(0.15))
                                .clipShape(Capsule())
                        }
                        if !J.str(entry.row, "frequency").isEmpty {
                            Image(systemName: "repeat")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                Spacer()
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }
}
