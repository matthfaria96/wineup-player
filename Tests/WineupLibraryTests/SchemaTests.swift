import Foundation
import GRDB
import Testing
@testable import WineupLibrary

struct SchemaTests {
    private func seedFile(_ db: Database) throws -> Int64 {
        var root = LibraryRootRecord(uuid: UUID().uuidString, path: "/r")
        try root.insert(db)
        var f = AudioFileRecord(rootID: root.id!, path: "/r/a.wav")
        try f.insert(db)
        return f.id!
    }

    @Test func migrationCreatesTables() async throws {
        try await withTempDir { dir in
            let db = try makeTempDatabase(in: dir)
            let names: Set<String> = try db.pool.read {
                Set(try String.fetchAll($0, sql: "SELECT name FROM sqlite_master WHERE type IN ('table')"))
            }
            for t in ["library_root", "audio_file", "artist", "release", "recording", "release_track",
                      "artwork", "lyrics", "tag_snapshot", "journal", "play_event", "track_mark",
                      "playlist", "playlist_item", "track_fts", "app_setting"] {
                #expect(names.contains(t), "falta \(t)")
            }
        }
    }

    @Test func releaseKindNeverInfersSingle() {
        #expect(ReleaseKind.resolve(tagValue: nil) == .unknown)
        #expect(ReleaseKind.resolve(tagValue: "Single") == .single)
        #expect(ReleaseKind.resolve(tagValue: "album") == .album)
        #expect(ReleaseKind.resolve(tagValue: "xyz") == .unknown)
    }

    @Test func restrictBlocksDeleteWithPlayEvent() async throws {
        try await withTempDir { dir in
            let db = try makeTempDatabase(in: dir)
            try db.pool.write { d in
                let id = try seedFile(d)
                var e = PlayEventRecord(audioFileID: id)
                try e.insert(d)
            }
            #expect(throws: DatabaseError.self) {
                try db.pool.write { try $0.execute(sql: "DELETE FROM audio_file") }
            }
        }
    }

    @Test func restrictBlocksDeleteWithPlaylistAndMark() async throws {
        try await withTempDir { dir in
            let db = try makeTempDatabase(in: dir)
            try db.pool.write { d in
                let id = try seedFile(d)
                var p = PlaylistRecord(name: "p")
                try p.insert(d)
                var item = PlaylistItemRecord(playlistID: p.id!, audioFileID: id, position: 0)
                try item.insert(d)
                var m = TrackMarkRecord(audioFileID: id, color: "red")
                try m.insert(d)
            }
            #expect(throws: DatabaseError.self) {
                try db.pool.write { try $0.execute(sql: "DELETE FROM audio_file") }
            }
        }
    }

    @Test func ftsFindsDiacriticInsensitive() async throws {
        try await withTempDir { dir in
            let db = try makeTempDatabase(in: dir)
            let hits: [Int64] = try db.pool.write { d in
                try d.execute(sql: "INSERT INTO track_fts(rowid,title,artist,album,genre) VALUES (1,?,?,?,?)",
                              arguments: ["Halo", "Beyoncé", "I Am", "Pop"])
                return try Int64.fetchAll(d, sql: "SELECT rowid FROM track_fts WHERE track_fts MATCH ?",
                                          arguments: ["beyonce*"])
            }
            #expect(hits == [1])
        }
    }
}
