import Foundation
import Testing
@testable import WineupLibrary

struct CollectionsStoreTests {
    private func seed(_ dir: URL) async throws -> (LibraryDatabase, CollectionsStore) {
        let db = try makeTempDatabase(in: dir)
        let r = try await SyntheticLibrary.addRoot(db)
        for (i, name) in ["a", "b", "c", "d"].enumerated() {
            let tags = ScannedTags(title: "T\(i)", artist: "Ana", album: "Alb", genre: "Rock", trackNumber: i + 1, discNumber: 1)
            _ = try await SyntheticLibrary.addTrack(db, rootID: r, name: "/m/\(name).mp3", tags: tags)
        }
        return (db, CollectionsStore(database: db))
    }

    @Test func playlistLifecycle() async throws {
        try await withTempDir { dir in
            let (_, store) = try await seed(dir)
            let list = try store.createPlaylist(named: "Estrada")
            #expect(try store.append(paths: ["/m/a.mp3", "/m/b.mp3", "/m/c.mp3", "/fora.mp3"], toPlaylist: list.id) == 3)
            let dup = try store.createPlaylist(named: "estrada")
            #expect(dup.name == "estrada (2)")

            try store.remove(path: "/m/b.mp3", fromPlaylist: list.id)
            #expect(try store.tracks(inPlaylist: list.id).map(\.path) == ["/m/a.mp3", "/m/c.mp3"])
            // As posições foram recompactadas: dá para acrescentar sem conflito.
            #expect(try store.append(paths: ["/m/d.mp3"], toPlaylist: list.id) == 1)
            #expect(try store.tracks(inPlaylist: list.id).map(\.path) == ["/m/a.mp3", "/m/c.mp3", "/m/d.mp3"])

            try store.renamePlaylist(id: list.id, to: "Viagem")
            #expect(try store.playlists().map(\.name).contains("Viagem"))
            try store.deletePlaylist(id: list.id)
            #expect(try store.playlists().map(\.name) == ["estrada (2)"])
        }
    }

    @Test func colorMarks() async throws {
        try await withTempDir { dir in
            let (_, store) = try await seed(dir)
            #expect(try store.setMark(path: "/m/a.mp3", color: "purple"))
            #expect(try store.setMark(path: "/m/b.mp3", color: "purple"))
            #expect(try store.setMark(path: "/m/c.mp3", color: "blue"))
            #expect(try store.setMark(path: "/nao-existe.mp3", color: "red") == false)
            #expect(try store.markCounts() == ["purple": 2, "blue": 1])
            #expect(try store.tracks(markedWith: "purple").count == 2)
            try store.setMark(path: "/m/a.mp3", color: nil)
            #expect(try store.marks()["/m/a.mp3"] == nil)
            #expect(try store.markCounts()["purple"] == 1)
        }
    }

    @Test func foldersAndResolve() async throws {
        try await withTempDir { dir in
            let (_, store) = try await seed(dir)
            #expect(try store.folders().map(\.path) == ["/m"])
            #expect(try store.resolvePath(path: "/outro/mac/T2.mp3", title: "T2", artist: "ana") == "/m/c.mp3")
        }
    }

    @Test func tracksUnderFolder() async throws {
        try await withTempDir { dir in
            let db = try makeTempDatabase(in: dir)
            let r = try await SyntheticLibrary.addRoot(db)
            for path in ["/m/rock/a.mp3", "/m/rock/sub/b.mp3", "/m/pop/c.mp3", "/m/rock_x/d.mp3", "/m/rock0/e.mp3", "/m/rock.mp3"] {
                let tags = ScannedTags(title: path, artist: "A", album: nil, genre: nil, trackNumber: nil, discNumber: nil)
                _ = try await SyntheticLibrary.addTrack(db, rootID: r, name: path, tags: tags)
            }
            let store = CollectionsStore(database: db)
            // Inclui subpastas; "_" e "%" no nome não viram curinga ("rock_x" fica de fora).
            #expect(Set(try store.tracks(under: "/m/rock").map(\.path)) == ["/m/rock/a.mp3", "/m/rock/sub/b.mp3"])
            #expect(try store.tracks(under: "/m").count == 6)
            #expect(try store.tracks(under: "/m/rock/").count == 2)
        }
    }

    @Test func tracksAtPathsInOneRead() async throws {
        try await withTempDir { dir in
            let (_, store) = try await seed(dir)
            let found = try store.tracks(atPaths: ["/m/a.mp3", "/m/c.mp3", "/m/a.mp3", "/fora.mp3"])
            #expect(Set(found.keys) == ["/m/a.mp3", "/m/c.mp3"])
            #expect(found["/m/c.mp3"]?.title == "T2")
            #expect(try store.tracks(atPaths: []).isEmpty)
        }
    }
}
