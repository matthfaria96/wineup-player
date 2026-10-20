import Foundation
import GRDB
@testable import WineupLibrary

/// Biblioteca sintética por inserção direta (sem arquivos reais).
enum SyntheticLibrary {
    static let genres = ["Rock", "Pop", "Jazz", "Blues", "Folk", "Metal", "Soul", "Funk",
                         "Reggae", "Classical", "Electronic", "Samba"]

    @discardableResult
    static func insert(count: Int, into db: LibraryDatabase, rootPath: String) async throws -> Int64 {
        let rootID: Int64 = try await db.pool.write { db in
            try db.execute(sql: "INSERT INTO library_root(uuid,path,online,added_at) VALUES (?,?,1,?)",
                           arguments: [UUID().uuidString, rootPath, Date()])
            return db.lastInsertedRowID
        }
        var start = 0
        while start < count {
            let end = min(start + 1000, count)
            try await db.pool.write { db in
                for i in start..<end {
                    try db.execute(sql: """
                        INSERT INTO audio_file(root_id,path,inode,size,mtime_ns,status,duration)
                        VALUES (?,?,?,?,?,'present',?)
                        """, arguments: [rootID, "\(rootPath)/d\(i % 200)/t\(i).mp3", i, 1000, 1, 200.0])
                    let fid = db.lastInsertedRowID
                    let artist = i % 7 == 0 ? "Beyoncé" : (i % 11 == 0 ? "Sigur Rós" : "Artist \(i % 500)")
                    let tags = ScannedTags(
                        title: "Track \(i) Halo", artist: artist, album: "Album \(i % 5000)",
                        genre: i % 13 == 0 ? nil : genres[i % genres.count],
                        trackNumber: i % 12 + 1, discNumber: 1, duration: 200)
                    try CatalogWriter.ingest(db, audioFileID: fid, tags: tags, fallbackTitle: "t\(i)")
                }
            }
            start = end
        }
        return rootID
    }

    /// Insere uma faixa avulsa (para testes pequenos).
    static func addTrack(_ db: LibraryDatabase, rootID: Int64, name: String, tags: ScannedTags,
                         status: String = "present") async throws -> Int64 {
        try await db.pool.write { db in
            try db.execute(sql: """
                INSERT INTO audio_file(root_id,path,size,mtime_ns,status) VALUES (?,?,1,1,?)
                """, arguments: [rootID, name, status])
            let fid = db.lastInsertedRowID
            try CatalogWriter.ingest(db, audioFileID: fid, tags: tags, fallbackTitle: name)
            if status == "missing" { try CatalogWriter.removeFromIndex(db, audioFileID: fid) }
            return fid
        }
    }

    static func addRoot(_ db: LibraryDatabase, path: String = "/m") async throws -> Int64 {
        try await db.pool.write { db in
            try db.execute(sql: "INSERT INTO library_root(uuid,path,online,added_at) VALUES (?,?,1,?)",
                           arguments: [UUID().uuidString, path, Date()])
            return db.lastInsertedRowID
        }
    }
}
