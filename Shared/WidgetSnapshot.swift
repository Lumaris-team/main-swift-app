import Foundation

/// Snapshot of workspace data shared with the widget extension through the
/// App Group. The app refreshes it on launch and after data loads; widgets
/// only read it (they cannot renew the single-use session token themselves).
struct WidgetSnapshot: Codable {
    struct Item: Codable {
        var title: String
        var sub: String
    }

    var updatedAt: Date = .distantPast

    // Tasks
    var tasksRemaining: Int = 0
    var tasksDueToday: Int = 0
    var taskItems: [Item] = []

    // Flashcards (SM-2)
    var cardsDue: Int = 0
    var cardsTotal: Int = 0

    // Next chapter test
    var nextTestTitle: String = ""
    var nextTestSubject: String = ""
    var nextTestDate: String = ""
    var nextTestDays: Int = -1

    // ÉcoleDirecte homeworks
    var homeworkOpen: Int = 0
    var homeworkItems: [Item] = []

    // ÉcoleDirecte grades
    var lastGradeTitle: String = ""
    var lastGradeSubject: String = ""
    var lastGradeValue: String = ""
    var lastGradeDate: String = ""
    var average: Double?
    var averageLabel: String = ""
}

enum WidgetSnapshotStore {
    static let suiteName = "group.com.danielersen.lumaris"
    static let dataKey = "widget_snapshot_v1"

    static var defaults: UserDefaults? { UserDefaults(suiteName: suiteName) }

    static func save(_ snapshot: WidgetSnapshot) {
        guard let defaults,
              let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: dataKey)
    }

    static func load() -> WidgetSnapshot? {
        guard let defaults, let data = defaults.data(forKey: dataKey) else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }

    static func clear() {
        defaults?.removeObject(forKey: dataKey)
    }
}
