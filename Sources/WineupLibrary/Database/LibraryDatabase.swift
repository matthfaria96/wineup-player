import Foundation
import GRDB

/// Banco SQLite da biblioteca (WAL via DatabasePool).
public final class LibraryDatabase: Sendable {
    public let pool: DatabasePool

    public init(path: String) throws {
        let parent = URL(fileURLWithPath: path).deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        var config = Configuration()
        config.foreignKeysEnabled = true
        config.prepareDatabase { db in
            try db.execute(sql: "PRAGMA synchronous=NORMAL")
        }
        pool = try DatabasePool(path: path, configuration: config)
        try LibraryMigrations.migrator.migrate(pool)
    }

    public static func defaultPath() throws -> String {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true)
        return base.appendingPathComponent("Wineup", isDirectory: true)
            .appendingPathComponent("library.sqlite").path
    }
}
