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

    let api: APIClient

    init(api: APIClient) { self.api = api }

    static let tableOrder = ["tasks", "repeat_tasks", "events", "repeat_events", "trash_tasks", "trash_events"]

    func loadAll() async {
        isLoading = true
        lastError = nil
        defer { isLoading = false }
        do {
            async let tasksResp = api.tasks("list", ["tables": Self.tableOrder])
            async let subjectsResp = api.subjects("list", ["all_chapters": true])
            async let metaResp = api.tasks("meta")
            let (t, s, m) = try await (tasksResp, subjectsResp, metaResp)
            if let tt = J.dict(t["tables"]) {
                tables = tt.mapValues { J.array($0) }
            } else {
                tables = [:]
            }
            subjects = J.array(s["subjects"])
            chapters = J.array(s["chapters"])
            meta = J.dict(m["meta"])?.mapValues { J.array($0) } ?? [:]
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
