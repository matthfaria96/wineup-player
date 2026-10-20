import Foundation
import GRDB
@testable import WineupLibrary

func withTempDir<T>(_ body: (URL) async throws -> T) async throws -> T {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("WineupServicesTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    return try await body(dir)
}

func makeTempDatabase(in dir: URL) throws -> LibraryDatabase {
    try LibraryDatabase(path: dir.appendingPathComponent("library.sqlite").path)
}

enum ServicesFixtures {
    @discardableResult
    static func insertTrack(db: LibraryDatabase, path: String, title: String, artist: String,
                            album: String?, duration: Double?, trackNumber: Int? = nil) throws -> Int64 {
        try db.pool.write { conn in
            let rootID: Int64
            if let existing = try Int64.fetchOne(conn, sql: "SELECT id FROM library_root LIMIT 1") {
                rootID = existing
            } else {
                try conn.execute(
                    sql: "INSERT INTO library_root (uuid, path, online, added_at) VALUES (?, ?, 1, ?)",
                    arguments: [UUID().uuidString, "/tmp/root-\(UUID().uuidString)", 0])
                rootID = conn.lastInsertedRowID
            }
            try conn.execute(sql: "INSERT INTO artist (name, sort_key) VALUES (?, ?) ON CONFLICT(sort_key) DO NOTHING",
                             arguments: [artist, artist.lowercased()])
            let artistID = try Int64.fetchOne(conn, sql: "SELECT id FROM artist WHERE sort_key = ?",
                                              arguments: [artist.lowercased()])!
            var releaseID: Int64?
            if let album {
                try conn.execute(
                    sql: "INSERT INTO release (title, album_artist_id) VALUES (?, ?) ON CONFLICT(title, album_artist_id) DO NOTHING",
                    arguments: [album, artistID])
                releaseID = try Int64.fetchOne(
                    conn, sql: "SELECT id FROM release WHERE title = ? AND album_artist_id = ?",
                    arguments: [album, artistID])
            }
            try conn.execute(sql: "INSERT INTO recording (title, artist_id, duration) VALUES (?, ?, ?)",
                             arguments: [title, artistID, duration])
            let recordingID = conn.lastInsertedRowID
            try conn.execute(
                sql: "INSERT INTO audio_file (root_id, path, size, mtime_ns, status, duration) VALUES (?, ?, 1, 0, 'present', ?)",
                arguments: [rootID, path, duration])
            let fileID = conn.lastInsertedRowID
            try conn.execute(
                sql: "INSERT INTO release_track (release_id, recording_id, audio_file_id, track_number) VALUES (?, ?, ?, ?)",
                arguments: [releaseID, recordingID, fileID, trackNumber])
            return fileID
        }
    }
}
