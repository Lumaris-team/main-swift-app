import Foundation

/// Workspace data store — mirrors `loadAll()` in workspace/script.js:
/// tasks tables + subjects/chapters + lookup metadata.
@MainActor
final class WorkspaceStore: ObservableObject {
    @Published var tables: [String: [[String: Any]]] = [:]
    @Published var subjects: [[String: Any]] = []
    @Published var chapters: [[String: Any]] = []
    @Published var meta: [String: [[String: Any]]] = [:]
    @Published var isLoading = false
    @Published var lastError: String?
    @Published var theme = AppTheme()

    let api: APIClient

    init(api: APIClient) { self.api = api }

    static let tableOrder = ["tasks", "repeat_tasks", "events", "repeat_events", "trash_tasks", "trash_events"]

    /// Populate the store from the on-disk mirror so the app works fully
    /// offline; the network refresh in loadAll() overwrites it.
    private func hydrateFromMirror() {
        let mirror = LocalMirror.shared
        var t: [String: [[String: Any]]] = [:]
        for table in Self.tableOrder {
            let rows = mirror.rows(database: "timetable", table: table)
            if !rows.isEmpty { t[table] = rows }
        }
        if !t.isEmpty { tables = t }
        let s = mirror.rows(database: "subjects_data", table: "subjects")
        if !s.isEmpty { subjects = s }
        let c = mirror.rows(database: "subjects_data", table: "chapters")
        if !c.isEmpty { chapters = c }
        let customization = mirror.rows(database: "settings", table: "customization")
        if let row = customization.first, !row.isEmpty {
            theme = AppTheme(settings: row)
        }
    }

    /// Rewrite the core tables to the mirror, then fetch /api/dump in the
    /// background to mirror every other D1 table (emails, school_data, …).
    private func persistAndDump(tasksTables: [String: [[String: Any]]],
                                subjectsRows: [[String: Any]],
                                chapterRows: [[String: Any]]) {
        let mirror = LocalMirror.shared
        for (table, rows) in tasksTables { mirror.save(database: "timetable", table: table, rows: rows) }
        mirror.save(database: "subjects_data", table: "subjects", rows: subjectsRows)
        mirror.save(database: "subjects_data", table: "chapters", rows: chapterRows)
        Task {
            guard let dump = try? await api.dump(),
                  let dbs = J.dict(dump["databases"]) else { return }
            for (db, tables) in dbs {
                guard let tableMap = tables as? [String: Any] else { continue }
                for (table, rows) in tableMap {
                    mirror.save(database: db, table: table, rows: rows)
                }
            }
        }
    }

    func loadAll() async {
        hydrateFromMirror()
        isLoading = true
        lastError = nil
        defer { isLoading = false }
        do {
            async let tasksResp = api.tasks("list", ["tables": Self.tableOrder])
            async let subjectsResp = api.subjects("list", ["all_chapters": true])
            async let metaResp = api.tasks("meta")
            async let settingsResp = api.call("api/settings/customization", method: "GET")
            let (t, s, m) = try await (tasksResp, subjectsResp, metaResp)
            if let tt = J.dict(t["tables"]) {
                tables = tt.mapValues { J.array($0) }
            } else {
                tables = [:]
            }
            subjects = J.array(s["subjects"])
            chapters = J.array(s["chapters"])
            meta = J.dict(m["meta"])?.mapValues { J.array($0) } ?? [:]
            if let resp = try? await settingsResp,
               let settings = J.dict(J.dict(resp)?["settings"]) {
                theme = AppTheme(settings: settings)
            }
            persistAndDump(tasksTables: tables, subjectsRows: subjects, chapterRows: chapters)
            // Refresh home-screen widgets with the fresh data (throttled).
            Task { await WidgetSync.refresh(store: self) }
        } catch {
            lastError = error.localizedDescription
        }
    }

    // MARK: - Row helpers

    func allRows() -> [(table: String, row: [String: Any])] {
        var out: [(String, [String: Any])] = []
        for table in Self.tableOrder where !table.hasPrefix("trash") {
            for row in tables[table] ?? [] { out.append((table, row)) }
        }
        return out
    }

    func chaptersOf(_ subjectId: Int) -> [[String: Any]] {
        chapters.filter { J.int($0, "subject_id") == subjectId }
    }

    func subjectName(_ id: Int) -> String {
        subjects.first { J.int($0, "subject_id") == id }.map { J.str($0, "subject_name") } ?? ""
    }

    func chapterName(_ id: Int) -> String {
        chapters.first { J.int($0, "lesson_id") == id }.map { J.str($0, "lesson_name") } ?? ""
    }

    // MARK: - Mutations

    func toggleDone(table: String, taskId: Int) async {
        _ = try? await api.tasks("toggle", ["table": table, "task_id": taskId])
        await loadAll()
    }

    func updateTask(table: String, taskId: Int, fields: [String: Any]) async throws {
        _ = try await api.tasks("update", ["table": table, "task_id": taskId, "fields": fields])
        await loadAll()
    }

    func deleteTask(table: String, taskId: Int) async {
        _ = try? await api.tasks("delete", ["table": table, "task_id": taskId])
        await loadAll()
    }

    func createTask(table: String, fields: [String: Any]) async throws {
        _ = try await api.tasks("create", ["table": table, "fields": fields])
        await loadAll()
    }

    func createSubject(fields: [String: Any]) async throws {
        _ = try await api.subjects("create-subject", ["fields": fields])
        await loadAll()
    }

    func updateSubject(subjectId: Int, fields: [String: Any]) async throws {
        _ = try await api.subjects("update-subject", ["subject_id": subjectId, "fields": fields])
        await loadAll()
    }

    func deleteSubject(subjectId: Int) async {
        _ = try? await api.subjects("delete-subject", ["subject_id": subjectId])
        await loadAll()
    }

    func createChapter(fields: [String: Any]) async throws {
        _ = try await api.subjects("create-chapter", ["fields": fields])
        await loadAll()
    }

    func updateChapter(lessonId: Int, fields: [String: Any]) async throws {
        _ = try await api.subjects("update-chapter", ["lesson_id": lessonId, "fields": fields])
        await loadAll()
    }

    func deleteChapter(lessonId: Int) async {
        _ = try? await api.subjects("delete-chapter", ["lesson_id": lessonId])
        await loadAll()
    }

    // MARK: - Lookup options (meta)

    func lookupOptions(_ key: String, idKey: String, nameKey: String = "name") -> [(id: Int, name: String, color: String)] {
        (meta[key] ?? []).map {
            (J.int($0, idKey), J.str($0, nameKey), J.str($0, "color"))
        }
    }

    func methodOptions() -> [(id: Int, name: String)] {
        lookupOptions("methods", idKey: "method_id").map { ($0.id, $0.name.isEmpty ? "Méthode \($0.id)" : $0.name) }
    }
}
