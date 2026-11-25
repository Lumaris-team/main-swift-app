import Foundation

/// JSON helpers — D1 rows arrive as `[String: Any]` with mixed types.
enum J {
    static func dict(_ any: Any?) -> [String: Any]? {
        any as? [String: Any]
    }

    static func array(_ any: Any?) -> [[String: Any]] {
        (any as? [[String: Any]]) ?? []
    }

    /// Row field accessors — D1 returns numbers as Int/Double/NSNumber and
    /// may send nulls or JSON-encoded strings for complex columns.
    static func str(_ row: [String: Any], _ key: String) -> String {
        guard let v = row[key], !(v is NSNull) else { return "" }
        if let s = v as? String { return s }
        if let n = v as? NSNumber { return n.stringValue }
        return "\(v)"
    }

    static func optStr(_ row: [String: Any], _ key: String) -> String? {
        let s = str(row, key)
        return s.isEmpty ? nil : s
    }

    static func int(_ row: [String: Any], _ key: String) -> Int {
        guard let v = row[key], !(v is NSNull) else { return 0 }
        if let n = v as? NSNumber { return n.intValue }
        if let s = v as? String, let i = Int(s) { return i }
        return 0
    }

    static func bool(_ row: [String: Any], _ key: String) -> Bool {
        guard let v = row[key], !(v is NSNull) else { return false }
        if let n = v as? NSNumber { return n.boolValue }
        if let s = v as? String { return s == "1" || s.lowercased() == "true" }
        return false
    }

    /// Tolerant date parser: ISO strings, "YYYY-MM-DD", sqlite datetime.
    static func date(_ row: [String: Any], _ key: String) -> Date? {
        let s = str(row, key)
        guard !s.isEmpty else { return nil }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = iso.date(from: s) { return d }
        iso.formatOptions = [.withInternetDateTime]
        if let d = iso.date(from: s.hasSuffix("Z") ? s : s + "Z") { return d }
        let day = DateFormatter()
        day.dateFormat = "yyyy-MM-dd"
        day.timeZone = .current
        if let d = day.date(from: String(s.prefix(10))) { return d }
        let sqlite = DateFormatter()
        sqlite.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return sqlite.date(from: s)
    }

    static func fmtDate(_ d: Date?) -> String {
        guard let d else { return "—" }
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        f.locale = Locale(identifier: "fr_FR")
        return f.string(from: d)
    }

    static func fmtDateTime(_ d: Date?) -> String {
        guard let d else { return "—" }
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        f.locale = Locale(identifier: "fr_FR")
        return f.string(from: d)
    }
}
