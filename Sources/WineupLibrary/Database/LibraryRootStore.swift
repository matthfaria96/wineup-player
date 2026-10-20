import Foundation
import GRDB
import WineupCore

/// Erros da biblioteca. Mensagens não incluem caminhos absolutos.
public enum LibraryError: Error, Sendable, Equatable {
    case rootNotFound
    case rootNotReadable
    case rootNotEmpty
    case outsideRoots
}

public struct LibraryRootStore: Sendable {
    let db: LibraryDatabase

    public init(db: LibraryDatabase) { self.db = db }

    @discardableResult
    public func addRoot(_ url: URL) throws -> LibraryRoot {
        let normalized = url.standardizedFileURL.resolvingSymlinksInPath()
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: normalized.path, isDirectory: &isDir), isDir.boolValue else {
            throw LibraryError.rootNotFound
        }
        guard FileManager.default.isReadableFile(atPath: normalized.path) else {
            throw LibraryError.rootNotReadable
        }
        let volume = try? normalized.resourceValues(forKeys: [.volumeUUIDStringKey]).volumeUUIDString
        let path = normalized.path
        return try db.pool.write { d in
            if let existing = try LibraryRootRecord.filter(Column("path") == path).fetchOne(d) {
                return Self.root(from: existing)
            }
            var rec = LibraryRootRecord(uuid: UUID().uuidString, path: path, volumeUUID: volume)
            try rec.insert(d)
            return Self.root(from: rec)
        }
    }

    public func roots() throws -> [LibraryRoot] {
        try db.pool.read { d in
            try LibraryRootRecord.order(Column("id")).fetchAll(d).map(Self.root(from:))
        }
    }

    public func removeRoot(id: UUID) throws {
        try db.pool.write { d in
            guard let rec = try LibraryRootRecord.filter(Column("uuid") == id.uuidString).fetchOne(d),
                  let rid = rec.id else { return }
            let count = try Int.fetchOne(d, sql: "SELECT COUNT(*) FROM audio_file WHERE root_id = ?",
                                         arguments: [rid]) ?? 0
            guard count == 0 else { throw LibraryError.rootNotEmpty }
            try d.execute(sql: "DELETE FROM library_root WHERE id = ?", arguments: [rid])
        }
    }

    private static func root(from rec: LibraryRootRecord) -> LibraryRoot {
        LibraryRoot(id: UUID(uuidString: rec.uuid) ?? UUID(), url: URL(fileURLWithPath: rec.path, isDirectory: true))
    }
}
