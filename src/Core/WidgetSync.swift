import Foundation
import WidgetKit

/// Builds the widget snapshot AND the Shortcuts JSON payloads from live
/// workspace + ÉcoleDirecte data, then pushes everything to the App Group.
/// Called after `WorkspaceStore.loadAll()` — throttled so frequent mutations
/// don't hammer the ED API — and forced on app launch. Every section is
/// best-effort: a failure keeps the rest.
@MainActor
enum WidgetSync {
    private static var lastRun: Date = .distantPast
    private static let minInterval: TimeInterval = 300 // 5 min

    private static let gradeTerms = ["trimestre1", "trimestre2", "trimestre3", "examen_blanc", "annee"]
    private static let termLabels = ["trimestre1": "T1", "trimestre2": "T2", "trimestre3": "T3", "examen_blanc": "EB", "annee": "Année"]
    private static let dayNames = ["dimanche", "lundi", "mardi", "mercredi", "jeudi", "vendredi", "samedi"]
    private static let dayOrder = ["lundi", "mardi", "mercredi", "jeudi", "vendredi", "samedi", "dimanche"]

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
                                sub: $0.subject.isEmpty ? J.fmtDate($0.date) : "\($0.subject) · \(J.fmtDate($0.date))")
        }

        // JSON: all open tasks
        saveJSON("tasksOpen", [
            "count": open.count,
            "tasks": open.map {
                ["title": $0.title, "date": isoDay($0.date), "subject": $0.subject]
            },
        ])

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
        saveJSON("nextTest", [
            "title": snap.nextTestTitle,
            "subject": snap.nextTestSubject,
            "date": snap.nextTestDate,
            "days": snap.nextTestDays,
        ])

        // --- Flashcards SM-2 ---
        if let status = try? await store.api.learning("review-status") {
            snap.cardsDue = J.int(status, "due")
            snap.cardsTotal = J.int(status, "total")
            saveJSON("flashcards", [
                "total": snap.cardsTotal, "due": snap.cardsDue,
                "mature": J.int(status, "mature"), "fresh": J.int(status, "fresh"),
            ])
        }

        // --- ÉcoleDirecte (best effort — may be slow or need QCM) ---
        await refreshED(store: store, snap: &snap)

        WidgetSnapshotStore.save(snap)
        WidgetCenter.shared.reloadAllTimelines()
    }

    // MARK: - ÉcoleDirecte: snapshot fields + JSON payloads

    private static func refreshED(store: WorkspaceStore, snap: inout WidgetSnapshot) async {
        async let gradesResp = try? store.api.ed("grades", headers: ["filter": "true"])
        async let averagesResp = try? store.api.ed("averages")
        async let hwResp = try? store.api.ed("homeworks", headers: ["filter": "true"])
        async let ttResp = try? store.api.ed("timetable", headers: ["filter": "true"])
        let (grades, averages, homeworks, timetable) = await (gradesResp, averagesResp, hwResp, ttResp)

        // ----- Grades -----
        var gradeItems: [[String: Any]] = []
        if let g = grades, !J.bool(g, "qcm_required") {
            gradeItems = flattenGrades(g)
            // Latest grade → widget
            if let latest = gradeItems.first {
                snap.lastGradeTitle = J.str(latest, "title")
                snap.lastGradeSubject = J.str(latest, "subject")
                snap.lastGradeValue = J.str(latest, "value20")
                snap.lastGradeDate = J.str(latest, "date")
            }
            // "New grades" = keys absent from the previous sync's seen set.
            let keys = Set(gradeItems.map { gradeKey($0) })
            if let seen = ShortcutJSONStore.seenGradeKeys() {
                let fresh = gradeItems.filter { !seen.contains(gradeKey($0)) }
                saveJSON("newGrades", [
                    "count": fresh.count,
                    "grades": fresh,
                ])
            } else {
                saveJSON("newGrades", ["count": 0, "grades": [], "note": "first_sync"])
            }
            ShortcutJSONStore.saveSeenGradeKeys(keys)
        }
        saveJSON("allGrades", ["count": gradeItems.count, "grades": gradeItems])

        // ----- Averages -----
        var avgPayload: [String: Any] = [:]
        if let a = averages, !J.bool(a, "qcm_required") {
            for (key, term) in a {
                guard let t = J.dict(term), let avg = t["moyenne_generale"] as? Double, avg > 0 else { continue }
                avgPayload[key] = (avg * 100).rounded() / 100
            }
            // Widget: prefer "annee"
            if let year = avgPayload["annee"] as? Double {
                snap.average = year
                snap.averageLabel = "Moyenne année"
            } else if let first = avgPayload.values.compactMap({ $0 as? Double }).first {
                snap.average = first
                snap.averageLabel = "Moyenne"
            }
        }
        saveJSON("averages", avgPayload)

        // ----- Homeworks -----
        var hwItems: [[String: Any]] = []
        if let h = homeworks, !J.bool(h, "qcm_required"), let byDate = J.dict(h["data"]) {
            for (date, listAny) in byDate {
                for d in J.array(listAny) {
                    let done = J.bool(d, "fait") || J.bool(d, "effectue")
                        || J.bool(J.dict(d["aFaire"]) ?? [:], "fait")
                    hwItems.append([
                        "date": date,
                        "title": hwTitle(d),
                        "subject": hwSubject(d),
                        "done": done,
                    ])
                }
            }
            hwItems.sort { J.str($0, "date") < J.str($1, "date") }
            let openHw = hwItems.filter { !J.bool($0, "done") }
            snap.homeworkOpen = openHw.count
            snap.homeworkItems = openHw.prefix(3).map {
                WidgetSnapshot.Item(title: J.str($0, "title"),
                                    sub: "\(J.str($0, "subject").isEmpty ? "" : "\(J.str($0, "subject")) · ")\(J.str($0, "date"))")
            }
        }
        saveJSON("homeworksOpen", [
            "count": hwItems.filter { !J.bool($0, "done") }.count,
            "items": hwItems.filter { !J.bool($0, "done") },
        ])

        // ----- Timetable: cancelled courses + today -----
        if let t = timetable, !J.bool(t, "qcm_required") {
            var cancelled: [[String: Any]] = []
            for (weekKey, weekLabel) in [("semaineA", "A"), ("semaineB", "B")] {
                guard let week = J.dict(t[weekKey]) else { continue }
                for day in dayOrder {
                    for c in J.array(week[day]) where isCancelled(c) {
                        cancelled.append([
                            "week": weekLabel, "day": day,
                            "subject": courseSubject(c),
                            "start": J.str(c, "horaireDebut"), "end": J.str(c, "horaireFin"),
                            "teacher": J.str(c, "enseignant"), "room": J.str(c, "salle"),
                        ])
                    }
                }
            }
            saveJSON("cancelledCourses", ["count": cancelled.count, "courses": cancelled])

            // Today's courses (current week, not cancelled)
            let todayName = dayNames[Calendar.current.component(.weekday, from: Date())]
            let todayCourses = J.array(J.dict(t["semaineA"])?[todayName])
                .filter { !isCancelled($0) }
                .sorted { J.str($0, "horaireDebut") < J.str($1, "horaireDebut") }
                .map { c in
                    [
                        "subject": courseSubject(c),
                        "start": J.str(c, "horaireDebut"), "end": J.str(c, "horaireFin"),
                        "teacher": J.str(c, "enseignant"), "room": J.str(c, "salle"),
                    ] as [String: Any]
                }
            saveJSON("todayCourses", ["day": todayName, "count": todayCourses.count, "courses": todayCourses])
        }
    }

    // MARK: - Payload builders

    /// Flatten the ED grades tree into a sorted list (most recent first).
    private static func flattenGrades(_ resp: [String: Any]) -> [[String: Any]] {
        var items: [[String: Any]] = []
        for (term, matieres) in resp {
            guard gradeTerms.contains(term), let subjects = J.dict(matieres) else { continue }
            for (subject, notesAny) in subjects {
                for n in J.array(notesAny) {
                    items.append([
                        "subject": subject,
                        "title": J.str(n, "titre").isEmpty ? "Évaluation" : J.str(n, "titre"),
                        "term": termLabels[term] ?? term,
                        "note": J.str(n, "note"),
                        "noteSur": J.str(n, "noteSur"),
                        "value20": gradeValue20(n),
                        "coefficient": J.str(n, "coefficient"),
                        "date": J.str(n, "date"),
                    ])
                }
            }
        }
        items.sort { J.str($0, "date") > J.str($1, "date") }
        return items
    }

    private static func gradeKey(_ g: [String: Any]) -> String {
        "\(J.str(g, "subject"))|\(J.str(g, "title"))|\(J.str(g, "date"))|\(J.str(g, "note"))"
    }

    private static func gradeValue20(_ n: [String: Any]) -> String {
        let v = J.str(n, "note").replacingOccurrences(of: ",", with: ".")
        let s = J.str(n, "noteSur").replacingOccurrences(of: ",", with: ".")
        guard let vn = Double(v), let sn = Double(s), sn > 0 else { return "" }
        return String(format: "%.1f/20", vn / sn * 20)
    }

    private static func isCancelled(_ c: [String: Any]) -> Bool {
        J.bool(c, "isAnnule") || J.str(c, "isAnnule") == "true"
    }

    private static func courseSubject(_ c: [String: Any]) -> String {
        let s = J.str(c, "matiereEnseignee")
        return s.isEmpty ? (J.str(c, "libelle").isEmpty ? "Cours" : J.str(c, "libelle")) : s
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

    // MARK: - JSON helpers

    private static func isoDay(_ d: Date?) -> String {
        guard let d else { return "" }
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: d)
    }

    private static func saveJSON(_ key: String, _ payload: [String: Any]) {
        var enriched = payload
        enriched["generated_at"] = ISO8601DateFormatter().string(from: Date())
        guard JSONSerialization.isValidJSONObject(enriched),
              let data = try? JSONSerialization.data(withJSONObject: enriched, options: [.prettyPrinted, .sortedKeys]),
              let json = String(data: data, encoding: .utf8) else { return }
        ShortcutJSONStore.save(key, json)
    }
}
