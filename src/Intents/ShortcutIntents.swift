import AppIntents
import Foundation

/// Shortcuts (Raccourcis) blocks — each returns the latest JSON payload the
/// app synced into the App Group. They run without opening the app and
/// without touching the session token (single-use, owned by the web
/// workspace). Run Lumaris once to refresh the data.
private func shortcutJSON(_ key: String) -> String {
    ShortcutJSONStore.load(key)
        ?? #"{"error":"Pas encore synchronisé — ouvrez Lumaris une fois pour générer les données."}"#
}

struct NewGradesIntent: AppIntent {
    static var title: LocalizedStringResource = "Lumaris — Nouvelles notes (JSON)"
    static var description = IntentDescription("Notes ÉcoleDirecte apparues depuis la dernière synchronisation, en JSON.")
    static var openAppWhenRun: Bool = false

    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        .result(value: shortcutJSON("newGrades"))
    }
}

struct AllGradesIntent: AppIntent {
    static var title: LocalizedStringResource = "Lumaris — Toutes les notes (JSON)"
    static var description = IntentDescription("Toutes les notes ÉcoleDirecte, triées de la plus récente à la plus ancienne, en JSON.")
    static var openAppWhenRun: Bool = false

    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        .result(value: shortcutJSON("allGrades"))
    }
}

struct AveragesIntent: AppIntent {
    static var title: LocalizedStringResource = "Lumaris — Moyennes (JSON)"
    static var description = IntentDescription("Moyennes par période (trimestres, année) ÉcoleDirecte, en JSON.")
    static var openAppWhenRun: Bool = false

    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        .result(value: shortcutJSON("averages"))
    }
}

struct CancelledCoursesIntent: AppIntent {
    static var title: LocalizedStringResource = "Lumaris — Cours annulés (JSON)"
    static var description = IntentDescription("Tous les cours annulés des semaines A et B, en JSON.")
    static var openAppWhenRun: Bool = false

    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        .result(value: shortcutJSON("cancelledCourses"))
    }
}

struct TodayCoursesIntent: AppIntent {
    static var title: LocalizedStringResource = "Lumaris — Cours du jour (JSON)"
    static var description = IntentDescription("Les cours d'aujourd'hui (semaine A, hors annulés), en JSON.")
    static var openAppWhenRun: Bool = false

    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        .result(value: shortcutJSON("todayCourses"))
    }
}

struct HomeworksOpenIntent: AppIntent {
    static var title: LocalizedStringResource = "Lumaris — Devoirs à rendre (JSON)"
    static var description = IntentDescription("Tous les devoirs ÉcoleDirecte non faits, triés par date, en JSON.")
    static var openAppWhenRun: Bool = false

    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        .result(value: shortcutJSON("homeworksOpen"))
    }
}

struct TasksOpenIntent: AppIntent {
    static var title: LocalizedStringResource = "Lumaris — Tâches restantes (JSON)"
    static var description = IntentDescription("Toutes les tâches et récurrentes non terminées, triées par échéance, en JSON.")
    static var openAppWhenRun: Bool = false

    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        .result(value: shortcutJSON("tasksOpen"))
    }
}

struct FlashcardsIntent: AppIntent {
    static var title: LocalizedStringResource = "Lumaris — Flashcards SM-2 (JSON)"
    static var description = IntentDescription("État de la répétition espacée : total, dues, matures et nouvelles cartes, en JSON.")
    static var openAppWhenRun: Bool = false

    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        .result(value: shortcutJSON("flashcards"))
    }
}

struct NextTestIntent: AppIntent {
    static var title: LocalizedStringResource = "Lumaris — Prochain test (JSON)"
    static var description = IntentDescription("Le chapitre dont le prochain contrôle arrive le plus tôt, en JSON.")
    static var openAppWhenRun: Bool = false

    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        .result(value: shortcutJSON("nextTest"))
    }
}
