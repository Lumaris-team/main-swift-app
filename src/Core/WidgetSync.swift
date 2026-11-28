import Foundation
import WidgetKit

/// Builds the widget snapshot from live workspace + ÉcoleDirecte data and
/// pushes it to the App Group. Called after `WorkspaceStore.loadAll()` —
/// throttled so frequent mutations don't hammer the ED API — and forced on
/// app launch. Every section is best-effort: a failure keeps the rest.
@MainActor
enum WidgetSync {
    private static var lastRun: Date = .distantPast
    private static let minInterval: TimeInterval = 300 // 5 min

    static func refresh(store: WorkspaceStore, force: Bool = false) async {
        if !force, Date().timeIntervalSince(lastRun) < minInterval { return }
        lastRun = Date()

        var snap = WidgetSnapshot()
        snap.updatedAt = Date()

        // --- Tasks (already loaded, no extra call) ---
        var open: [(title: String, date: Date?, subject: String)] = []
        var today = 0
        let cal = Calendar.current
        for table in ["tasks", "repeat_tasks"] {
            for row in store.tables[table] ?? [] where !J.bool(row, "is_done") {
                let title = J.str(row, "title")
                guard !title.isEmpty else { continue }
                let d = J.date(row, "remind_date")
                let subject = store.subjectName(J.int(row, "subject_id"))
                open.append((title, d, subject))
                if let d, cal.isDateInToday(d) { today += 1 }
            }
        }
        open.sort {
            switch ($0.date, $1.date) {
            case let (a?, b?): return a < b
            case (_?, nil): return true
            case (nil, _?): return false
            default: return $0.title < $1.title
            }
        }
        snap.tasksRemaining = open.count
        snap.tasksDueToday = today
        snap.taskItems = open.prefix(4).map {
            WidgetSnapshot.Item(title: $0.title,
                                sub: $0.subject.isEmpty ? (J.fmtDate($0.date)) : "\($0.subject) · \(J.fmtDate($0.date))")
        }

        // --- Next chapter test ---
        let upcoming = store.chapters
            .compactMap { c -> (name: String, subject: String, date: Date)? in
                guard let d = J.date(c, "tests_date"), d >= cal.startOfDay(for: Date()) else { return nil }
                return (J.str(c, "lesson_name"), store.subjectName(J.int(c, "subject_id")), d)
            }
            .sorted { $0.date < $1.date }
        if let next = upcoming.first {
            snap.nextTestTitle = next.name
            snap.nextTestSubject = next.subject
            snap.nextTestDate = J.fmtDate(next.date)
            snap.nextTestDays = cal.dateComponents([.day], from: cal.startOfDay(for: Date()), to: cal.startOfDay(for: next.date)).day ?? -1
        }

        // --- Flashcards SM-2 ---
        if let status = try? await store.api.learning("review-status") {
            snap.cardsDue = J.int(status, "due")
            snap.cardsTotal = J.int(status, "total")
        }

        // --- ÉcoleDirecte (best effort — may be slow or need QCM) ---
        await refreshGrades(store: store, snap: &snap)
        await refreshHomeworks(store: store, snap: &snap)

        WidgetSnapshotStore.save(snap)
        WidgetCenter.shared.reloadAllTimelines()
    }

    // MARK: - ÉcoleDirecte sections

    private static func refreshGrades(store: WorkspaceStore, snap: inout WidgetSnapshot) async {
        // Latest grade across all terms/subjects, sorted by date desc.
        if let grades = try? await store.api.ed("grades", headers: ["filter": "true"]),
           !J.bool(grades, "qcm_required") {
            var best: (date: String, title: String, subject: String, value: String)?
            for (term, matieres) in grades {
                guard ["trimestre1", "trimestre2", "trimestre3", "examen_blanc", "annee"].contains(term),
                      let subjects = J.dict(matieres) else { continue }
                for (subject, notesAny) in subjects {
                    for note in J.array(notesAny) {
                        let date = J.str(note, "date")
                        guard !date.isEmpty else { continue }
                        let value = gradeValue(note)
                        let title = J.str(note, "titre").isEmpty ? "Évaluation" : J.str(note, "titre")
                        if best == nil || date > best!.date {
                            best = (date, title, subject, value)
                        }
                    }
                }
            }
            if let b = best {
                snap.lastGradeTitle = b.title
                snap.lastGradeSubject = b.subject
                snap.lastGradeValue = b.value
                snap.lastGradeDate = b.date
            }
        }

        // General average — prefer "annee", fall back to any numeric term.
        if let averages = try? await store.api.ed("averages"), !J.bool(averages, "qcm_required") {
            var candidates: [(key: String, avg: Double)] = []
            for (key, term) in averages {
                guard let t = J.dict(term), let avg = t["moyenne_generale"] as? Double, avg > 0 else { continue }
                candidates.append((key, avg))
            }
            if let pick = candidates.first(where: { $0.key == "annee" }) ?? candidates.first {
                snap.average = pick.avg
                snap.averageLabel = pick.key == "annee" ? "Moyenne année" : "Moyenne \(pick.key)"
            }
        }
    }

    private static func gradeValue(_ note: [String: Any]) -> String {
        let v = J.str(note, "note").replacingOccurrences(of: ",", with: ".")
        let s = J.str(note, "noteSur").replacingOccurrences(of: ",", with: ".")
        guard let vn = Double(v), let sn = Double(s), sn > 0 else { return "" }
        return String(format: "%.1f/%.0f", vn / sn * 20, sn)
    }

    private static func refreshHomeworks(store: WorkspaceStore, snap: inout WidgetSnapshot) async {
        guard let resp = try? await store.api.ed("homeworks", headers: ["filter": "true"]),
              !J.bool(resp, "qcm_required"),
              let byDate = J.dict(resp["data"]) else { return }

        var open: [(date: String, title: String, subject: String)] = []
        for (date, listAny) in byDate {
            for d in J.array(listAny) {
                let done = J.bool(d, "fait") || J.bool(d, "effectue")
                    || J.bool(J.dict(d["aFaire"]) ?? [:], "fait")
                guard !done else { continue }
                let title = hwTitle(d)
                guard !title.isEmpty else { continue }
                open.append((date, title, hwSubject(d)))
            }
        }
        open.sort { $0.date < $1.date }
        snap.homeworkOpen = open.count
        snap.homeworkItems = open.prefix(3).map {
            WidgetSnapshot.Item(title: $0.title, sub: "\($0.subject.isEmpty ? "" : "\($0.subject) · ")\($0.date)")
        }
    }

    private static func hwTitle(_ d: [String: Any]) -> String {
        for key in ["titre", "intitule", "devoir", "contenu"] {
            let s = J.str(d, key)
            if !s.isEmpty { return s }
        }
        if let af = J.dict(d["aFaire"]), let s = J.optStr(af, "devoir") { return s }
        if let af = J.dict(d["aFaire"]), let s = J.optStr(af, "intitule") { return s }
        return ""
    }

    private static func hwSubject(_ d: [String: Any]) -> String {
        if let m = J.dict(d["matiere"]), let s = J.optStr(m, "libelle") ?? J.optStr(m, "nom") { return s }
        return J.str(d, "matiereEnseignement")
    }
}
