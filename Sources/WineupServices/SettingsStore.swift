import Foundation
import GRDB
import WineupLibrary

/// Acesso chave/valor a `app_setting`.
public struct SettingsStore: Sendable {
    public enum Keys {
        public static let showColorTags = "playlists.showColorTags"
        public static let dedupePlayAll = "playback.dedupePlayAll"
        public static let session = "session.v1"
    }

    private let db: LibraryDatabase

    public init(db: LibraryDatabase) { self.db = db }

    public func string(_ key: String) throws -> String? {
        try db.pool.read { conn in
            try String.fetchOne(conn, sql: "SELECT value FROM app_setting WHERE key = ?", arguments: [key])
        }
    }

    public func set(_ key: String, _ value: String) throws {
        try db.pool.write { conn in
            try conn.execute(
                sql: "INSERT INTO app_setting (key, value) VALUES (?, ?) ON CONFLICT(key) DO UPDATE SET value = excluded.value",
                arguments: [key, value])
        }
    }

    public func remove(_ key: String) throws {
        try db.pool.write { conn in
            try conn.execute(sql: "DELETE FROM app_setting WHERE key = ?", arguments: [key])
        }
    }

    public func bool(_ key: String, default fallback: Bool) throws -> Bool {
        guard let raw = try string(key) else { return fallback }
        switch raw {
        case "1", "true": return true
        case "0", "false": return false
        default: return fallback
        }
    }

    public func setBool(_ key: String, _ value: Bool) throws {
        try set(key, value ? "1" : "0")
    }

    public func all(prefix: String) throws -> [String: String] {
        try db.pool.read { conn in
            let escaped = prefix.replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "%", with: "\\%")
                .replacingOccurrences(of: "_", with: "\\_")
            let rows = try Row.fetchAll(
                conn, sql: "SELECT key, value FROM app_setting WHERE key LIKE ? ESCAPE '\\'",
                arguments: [escaped + "%"])
            return Dictionary(uniqueKeysWithValues: rows.map { ($0["key"] as String, $0["value"] as String) })
        }
    }
}
