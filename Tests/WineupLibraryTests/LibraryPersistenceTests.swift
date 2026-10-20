import Foundation
import GRDB
import Testing
@testable import WineupLibrary

struct LibraryPersistenceTests {
    private func makeFile(_ db: LibraryDatabase, root: Int64, name: String) throws -> Int64 {
        try db.pool.write { d in
            var f = AudioFileRecord(rootID: root, path: "/m/\(name)")
            try f.insert(d)
            return f.id!
        }
    }

    private func rootID(_ db: LibraryDatabase) throws -> Int64 {
        try db.pool.read { try Int64.fetchOne($0, sql: "SELECT id FROM library_root")! }
    }

    @Test func addRootIsIdempotent() async throws {
        try await withTempDir { dir in
            let music = dir.appendingPathComponent("Music", isDirectory: true)
            try FileManager.default.createDirectory(at: music, withIntermediateDirectories: true)
            let store = LibraryRootStore(db: try makeTempDatabase(in: dir))
            let a = try store.addRoot(music)
            let b = try store.addRoot(URL(fileURLWithPath: music.path + "/"))
            let c = try store.addRoot(music.appendingPathComponent("../Music"))
            #expect(a.id == b.id && b.id == c.id)
            #expect(try store.roots().count == 1)
        }
    }

    @Test func addRootMissingFolderThrows() async throws {
        try await withTempDir { dir in
            let store = LibraryRootStore(db: try makeTempDatabase(in: dir))
            #expect(throws: LibraryError.rootNotFound) {
                try store.addRoot(dir.appendingPathComponent("nope"))
            }
        }
    }

    @Test func persistsAcrossReopen() async throws {
        try await withTempDir { dir in
            let music = dir.appendingPathComponent("Music", isDirectory: true)
            try FileManager.default.createDirectory(at: music, withIntermediateDirectories: true)
            do {
                let db = try makeTempDatabase(in: dir)
                _ = try LibraryRootStore(db: db).addRoot(music)
                let fid = try makeFile(db, root: try rootID(db), name: "a.wav")
                try db.pool.write {
                    try CatalogWriter.ingest($0, audioFileID: fid,
                        tags: ScannedTags(title: "Halo", artist: "Beyoncé", album: "I Am"),
                        fallbackTitle: "a")
                }
            }
            let db2 = try makeTempDatabase(in: dir)
            #expect(try LibraryRootStore(db: db2).roots().count == 1)
            let row = try db2.pool.read {
                try Row.fetchOne($0, sql: """
                    SELECT r.title t, a.name n, rel.title al FROM release_track rt
                    JOIN recording r ON r.id = rt.recording_id
                    JOIN artist a ON a.id = r.artist_id
                    JOIN release rel ON rel.id = rt.release_id
                    """)
            }
            #expect(row?["t"] == "Halo" && row?["n"] == "Beyoncé" && row?["al"] == "I Am")
        }
    }

    @Test func ingestIsIdempotentAndSharesArtistAndRelease() async throws {
        try await withTempDir { dir in
            let db = try makeTempDatabase(in: dir)
            let store = LibraryRootStore(db: db)
            let music = dir.appendingPathComponent("M", isDirectory: true)
            try FileManager.default.createDirectory(at: music, withIntermediateDirectories: true)
            _ = try store.addRoot(music)
            let rid = try rootID(db)
            let f1 = try makeFile(db, root: rid, name: "1.wav")
            let f2 = try makeFile(db, root: rid, name: "2.wav")
            try db.pool.write { d in
                for _ in 0..<2 {
                    try CatalogWriter.ingest(d, audioFileID: f1,
                        tags: ScannedTags(title: "A", artist: "Beyoncé", album: "X"), fallbackTitle: "1")
                }
                try CatalogWriter.ingest(d, audioFileID: f2,
                    tags: ScannedTags(title: "B", artist: "beyonce", album: "X", releaseType: "Single"),
                    fallbackTitle: "2")
            }
            func count(_ sql: String) throws -> Int {
                try db.pool.read { try Int.fetchOne($0, sql: sql)! }
            }
            #expect(try count("SELECT COUNT(*) FROM release_track") == 2)
            #expect(try count("SELECT COUNT(*) FROM track_fts") == 2)
            #expect(try count("SELECT COUNT(*) FROM artist") == 1)
            #expect(try count("SELECT COUNT(*) FROM release") == 1)
            // kind vem da primeira ingestão (sem tag): unknown, nunca single inferido
            let kind = try db.pool.read { try String.fetchOne($0, sql: "SELECT kind FROM release") }
            #expect(kind == "unknown")
            try db.pool.write { try CatalogWriter.removeFromIndex($0, audioFileID: f1) }
            #expect(try count("SELECT COUNT(*) FROM track_fts") == 1)
            #expect(try count("SELECT COUNT(*) FROM audio_file") == 2)
        }
    }
}
