import Foundation

/// Local mirror of the account's D1 databases — one JSON file per table
/// under Application Support/LumarisDB/<database>/<table>.json.
/// The app reads from here first (instant + offline), then refreshes
/// from the API and rewrites the files.
final class LocalMirror {
    static let shared = LocalMirror()

    let root: URL

    private init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        root = base.appendingPathComponent("LumarisDB", isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    private func fileURL(database: String, table: String) -> URL {
        root.appendingPathComponent(database, isDirectory: true)
            .appendingPathComponent("\(table).json")
    }

    /// Persist one table's rows (array of row dicts) as pretty JSON.
    func save(database: String, table: String, rows: Any) {
        let dir = root.appendingPathComponent(database, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        guard JSONSerialization.isValidJSONObject(rows),
              let data = try? JSONSerialization.data(withJSONObject: rows, options: [.prettyPrinted, .sortedKeys]) else { return }
        try? data.write(to: fileURL(database: database, table: table), options: .atomic)
    }

    /// All tables of one database: { tableName: parsedJSON }.
    func loadDatabase(_ database: String) -> [String: Any] {
        let dir = root.appendingPathComponent(database, isDirectory: true)
        guard let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { return [:] }
        var out: [String: Any] = [:]
        for file in files where file.pathExtension == "json" {
            let table = file.deletingPathExtension().lastPathComponent
            if let data = try? Data(contentsOf: file),
               let json = try? JSONSerialization.jsonObject(with: data) {
                out[table] = json
            }
        }
        return out
    }

    /// Convenience: rows of one table as [[String: Any]].
    func rows(database: String, table: String) -> [[String: Any]] {
        guard let data = try? Data(contentsOf: fileURL(database: database, table: table)),
              let json = try? JSONSerialization.jsonObject(with: data) else { return [] }
        if let arr = json as? [[String: Any]] { return arr }
        if let arr = json as? [Any] { return arr.compactMap { $0 as? [String: Any] } }
        return []
    }

    /// First row of a table as a dict (settings-style singletons).
    func row(database: String, table: String) -> [String: Any] {
        rows(database: database, table: table).first ?? [:]
    }
}
