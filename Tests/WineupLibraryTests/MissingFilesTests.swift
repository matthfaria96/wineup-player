import Foundation
import GRDB
import Testing
@testable import WineupLibrary

struct MissingFilesTests {
    private func setup(_ dir: URL, files: [String]) throws -> (LibraryDatabase, URL, UUID) {
        let db = try makeTempDatabase(in: dir)
        let music = dir.appendingPathComponent("Music", isDirectory: true)
        try FileManager.default.createDirectory(at: music, withIntermediateDirectories: true)
        for (i, n) in files.enumerated() {
            try WAVFixture.write(to: music.appendingPathComponent(n), seconds: 0.02 + Double(i) * 0.01)
        }
        let root = try LibraryRootStore(db: db).addRoot(music)
        return (db, music, root.id)
    }

    @Test func movedFileKeepsIDAndPlayEvents() async throws {
        try await withTempDir { dir in
            let (db, music, id) = try setup(dir, files: ["a.wav", "b.wav", "c.wav"])
            let scanner = Scanner(database: db)
            _ = try await scanner.scan(rootID: id, progress: { _ in })
            let aID = try await db.pool.read { try Int64.fetchOne($0, sql: "SELECT id FROM audio_file WHERE path LIKE '%/a.wav'")! }
            try await db.pool.write { var e = PlayEventRecord(audioFileID: aID); try e.insert($0) }
            try FileManager.default.createDirectory(at: music.appendingPathComponent("sub"), withIntermediateDirectories: true)
            try FileManager.default.moveItem(at: music.appendingPathComponent("a.wav"),
                                             to: music.appendingPathComponent("sub/a2.wav"))
            let p = try await scanner.scan(rootID: id, progress: { _ in })
            #expect(p.moved == 1 && p.read == 0 && p.missing == 0)
            let rows: [AudioFileRecord] = try await db.pool.read { try AudioFileRecord.fetchAll($0) }
            #expect(rows.count == 3)
            let moved = rows.first { $0.id == aID }
            #expect(moved?.path.hasSuffix("/sub/a2.wav") == true)
            #expect(moved?.status == "present")
        }
    }

    @Test func deletedBecomesMissingAndComesBack() async throws {
        try await withTempDir { dir in
            let (db, music, id) = try setup(dir, files: ["a.wav", "b.wav"])
            let scanner = Scanner(database: db)
            _ = try await scanner.scan(rootID: id, progress: { _ in })
            let aID = try await db.pool.read { try Int64.fetchOne($0, sql: "SELECT id FROM audio_file WHERE path LIKE '%/a.wav'")! }
            try await db.pool.write { var e = PlayEventRecord(audioFileID: aID); try e.insert($0) }
            let backup = dir.appendingPathComponent("a.bak")
            try FileManager.default.moveItem(at: music.appendingPathComponent("a.wav"), to: backup)
            let p = try await scanner.scan(rootID: id, progress: { _ in })
            #expect(p.missing == 1)
            let (st, since, plays, fts) = try await db.pool.read { d in
                (try String.fetchOne(d, sql: "SELECT status FROM audio_file WHERE id = ?", arguments: [aID]),
                 try Date.fetchOne(d, sql: "SELECT missing_since FROM audio_file WHERE id = ?", arguments: [aID]),
                 try Int.fetchOne(d, sql: "SELECT COUNT(*) FROM play_event WHERE audio_file_id = ?", arguments: [aID]),
                 try Int.fetchOne(d, sql: "SELECT COUNT(*) FROM track_fts WHERE rowid = ?", arguments: [aID]))
            }
            #expect(st == "missing" && since != nil && plays == 1 && fts == 0)
            try FileManager.default.moveItem(at: backup, to: music.appendingPathComponent("a.wav"))
            _ = try await scanner.scan(rootID: id, progress: { _ in })
            let (st2, fts2) = try await db.pool.read { d in
                (try String.fetchOne(d, sql: "SELECT status FROM audio_file WHERE id = ?", arguments: [aID]),
                 try Int.fetchOne(d, sql: "SELECT COUNT(*) FROM track_fts WHERE rowid = ?", arguments: [aID]))
            }
            #expect(st2 == "present" && fts2 == 1)
        }
    }

    @Test func unreachableRootGoesOfflineWithoutMissing() async throws {
        try await withTempDir { dir in
            let (db, music, id) = try setup(dir, files: ["a.wav", "b.wav"])
            let scanner = Scanner(database: db)
            _ = try await scanner.scan(rootID: id, progress: { _ in })
            let gone = dir.appendingPathComponent("Gone")
            try FileManager.default.moveItem(at: music, to: gone)
            let p = try await scanner.scan(rootID: id, progress: { _ in })
            #expect(p.finished && p.missing == 0)
            let (online, present) = try await db.pool.read { d in
                (try Int.fetchOne(d, sql: "SELECT online FROM library_root"),
                 try Int.fetchOne(d, sql: "SELECT COUNT(*) FROM audio_file WHERE status = 'present'"))
            }
            #expect(online == 0 && present == 2)
            try FileManager.default.moveItem(at: gone, to: music)
            _ = try await scanner.scan(rootID: id, progress: { _ in })
            let back = try await db.pool.read { try Int.fetchOne($0, sql: "SELECT online FROM library_root") }
            #expect(back == 1)
        }
    }
}
