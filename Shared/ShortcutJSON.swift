import Foundation

/// Pre-computed JSON payloads for Shortcuts App Intents, stored in the App
/// Group next to the widget snapshot. `WidgetSync` regenerates them on every
/// sync; intents just read the latest strings — no auth needed at run time.
enum ShortcutJSONStore {
    static let keys = [
        "newGrades", "allGrades", "averages", "cancelledCourses",
        "todayCourses", "homeworksOpen", "tasksOpen", "flashcards", "nextTest",
    ]

    private static func storageKey(_ key: String) -> String { "shortcut_\(key)" }

    static func save(_ key: String, _ json: String) {
        WidgetSnapshotStore.defaults?.set(json, forKey: storageKey(key))
    }

    static func load(_ key: String) -> String? {
        WidgetSnapshotStore.defaults?.string(forKey: storageKey(key))
    }

    static func clearAll() {
        for key in keys { WidgetSnapshotStore.defaults?.removeObject(forKey: storageKey(key)) }
        WidgetSnapshotStore.defaults?.removeObject(forKey: seenGradesKey)
    }

    // MARK: - "New grades" diff state

    static let seenGradesKey = "shortcut_seen_grade_keys"

    /// Grade keys already reported. Absent key = first sync → nothing is
    /// "new" yet (avoids reporting the whole history on first run).
    static func seenGradeKeys() -> Set<String>? {
        guard let data = WidgetSnapshotStore.defaults?.data(forKey: seenGradesKey),
              let arr = try? JSONDecoder().decode([String].self, from: data) else { return nil }
        return Set(arr)
    }

    static func saveSeenGradeKeys(_ keys: Set<String>) {
        guard let data = try? JSONEncoder().encode(Array(keys.suffix(500))) else { return }
        WidgetSnapshotStore.defaults?.set(data, forKey: seenGradesKey)
    }
}
