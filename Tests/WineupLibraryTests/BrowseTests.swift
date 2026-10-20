import Foundation
import GRDB
import Testing
@testable import WineupLibrary

struct BrowseTests {
    private func seed(_ dir: URL) async throws -> (LibraryDatabase, Int64) {
        let db = try makeTempDatabase(in: dir)
        let r = try await SyntheticLibrary.addRoot(db)
        func t(_ p: String, _ title: String, _ artist: String, _ album: String?, _ genre: String?, _ n: Int?, _ disc: Int? = 1) -> ScannedTags {
            ScannedTags(title: title, artist: artist, album: album, genre: genre, trackNumber: n, discNumber: disc)
        }
        _ = try await SyntheticLibrary.addTrack(db, rootID: r, name: "/m/x/1.mp3", tags: t("", "A2", "Ana", "Alb", "Rock", 2))
        _ = try await SyntheticLibrary.addTrack(db, rootID: r, name: "/m/x/2.mp3", tags: t("", "A1", "Ana", "Alb", "Rock", 1))
        _ = try await SyntheticLibrary.addTrack(db, rootID: r, name: "/m/y/3.mp3", tags: t("", "Solo", "Bob", "OneOff", nil, 1))
        _ = try await SyntheticLibrary.addTrack(db, rootID: r, name: "/m/y/4.mp3", tags: t("", "Loose", "Bob", nil, "", nil))
        _ = try await SyntheticLibrary.addTrack(db, rootID: r, name: "/m/y/5.mp3", tags: t("", "Gone", "Bob", "Alb2", "Pop", 1), status: "missing")
        return (db, r)
    }

    @Test func dimensions() async throws {
        try await withTempDir { dir in
            let (db, r) = try await seed(dir)
            let b = BrowseService(database: db)
            let artists = try await b.artists()
            #expect(artists.map(\.name) == ["Ana", "Bob"] && artists.map(\.trackCount) == [2, 2])
            let ana = try await b.tracks(artistID: artists[0].id)
            #expect(ana.count == 2)
            let albums = try await b.albums()
            #expect(albums.count == 3 && albums.first { $0.title == "Alb" }?.trackCount == 2)
            let alb = albums.first { $0.title == "Alb" }!
            #expect(try await b.tracks(releaseID: alb.id).map(\.title) == ["A1", "A2"])
            let genres = try await b.genres()
            #expect(genres.first { $0.name == BrowseService.uncategorizedGenre }?.trackCount == 2)
            #expect(genres.first { $0.name == "Rock" }?.trackCount == 2)
            #expect(genres.first { $0.name == "Pop" } == nil)
            #expect(try await b.tracks(genre: "Sem categoria").count == 2)
            #expect(try await b.tracks(genre: "Rock").count == 2)
            let folders = try await b.folders(rootID: r)
            #expect(folders == [FolderSummary(path: "/m/x", trackCount: 2), FolderSummary(path: "/m/y", trackCount: 2)])
            #expect(try await b.tracks(inFolder: "/m/y").count == 2)
            #expect(try await b.allTracks().count == 4)
            #expect(try await b.allTracks(limit: 2, offset: 3).count == 1)
            #expect(try await b.allTracks(includeMissing: true).count == 5)
        }
    }

    @Test func singlesAreVirtualAndWriteNothing() async throws {
        try await withTempDir { dir in
            let (db, _) = try await seed(dir)
            let count: () async throws -> [Int] = {
                try await db.pool.read { db in
                    [try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM release")!,
                     try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM release_track")!]
                }
            }
            let before = try await count()
            let b = BrowseService(database: db)
            let singles = try await b.singles()
            #expect(Set(singles.map(\.title)) == ["Solo", "Loose"])
            let s = try await b.singlesSummary()
            #expect(s.id == -1 && s.title == "Singles" && s.trackCount == 2)
            #expect(try await count() == before)
        }
    }
}
