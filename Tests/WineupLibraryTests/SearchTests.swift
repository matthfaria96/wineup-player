import Foundation
import Testing
@testable import WineupLibrary

struct SearchTests {
    private func seed(_ dir: URL) async throws -> (LibraryDatabase, Int64) {
        let db = try makeTempDatabase(in: dir)
        let r = try await SyntheticLibrary.addRoot(db)
        _ = try await SyntheticLibrary.addTrack(db, rootID: r, name: "/m/a.mp3", tags: ScannedTags(title: "Crazy", artist: "Beyoncé", album: "B"))
        _ = try await SyntheticLibrary.addTrack(db, rootID: r, name: "/m/b.mp3", tags: ScannedTags(title: "Svefn", artist: "Sigur", album: "Rós"))
        _ = try await SyntheticLibrary.addTrack(db, rootID: r, name: "/m/c.mp3", tags: ScannedTags(title: "Halo", artist: "X", album: "Y"))
        _ = try await SyntheticLibrary.addTrack(db, rootID: r, name: "/m/d.mp3", tags: ScannedTags(title: "Halo Gone", artist: "X", album: "Y"), status: "missing")
        return (db, r)
    }

    @Test func accentInsensitive() async throws {
        try await withTempDir { dir in
            let (db, _) = try await seed(dir)
            let s = SearchService(database: db)
            #expect(try await s.search("beyonce").map(\.title) == ["Crazy"])
            #expect(try await s.search("ros").map(\.title) == ["Svefn"])
            #expect(try await s.search("hal").map(\.title) == ["Halo"])
        }
    }

    @Test func hostileInputNeverThrows() async throws {
        try await withTempDir { dir in
            let (db, _) = try await seed(dir)
            let s = SearchService(database: db)
            for q in ["\"", "a* -b", "AND", "OR", "(x", "NEAR", "NEAR(a b)", "title:x", "^", "'; DROP TABLE audio_file;--", "***"] {
                _ = try await s.search(q)
            }
            #expect(try await s.search("").isEmpty)
            #expect(try await s.search("  \"* ").isEmpty)
            let n = try await db.pool.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM audio_file")! }
            #expect(n == 4)
        }
    }

    @Test func missingExcluded() async throws {
        try await withTempDir { dir in
            let (db, _) = try await seed(dir)
            #expect(try await SearchService(database: db).search("gone").isEmpty)
        }
    }
}
