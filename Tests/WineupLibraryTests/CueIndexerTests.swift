import Foundation
import Testing
@testable import WineupLibrary
import WineupCore

struct CueIndexerTests {
    private func setUp(_ dir: URL) throws -> (LibraryDatabase, LibraryRoot, URL, URL) {
        let root = dir.appendingPathComponent("musica", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let wav = root.appendingPathComponent("show.wav")
        try WAVFixture.write(to: wav, seconds: 4)
        let cue = root.appendingPathComponent("show.cue")
        try """
        PERFORMER "Banda"
        TITLE "Ao Vivo"
        FILE "show.wav" WAVE
          TRACK 01 AUDIO
            TITLE "Abertura"
            INDEX 01 00:00:00
          TRACK 02 AUDIO
            TITLE "Final"
            INDEX 01 00:02:00
        """.write(to: cue, atomically: true, encoding: .utf8)
        let db = try makeTempDatabase(in: dir)
        let r = try LibraryRootStore(db: db).addRoot(root)
        return (db, r, wav, cue)
    }

    @Test func cueTracksEnterLibraryAndHideTheWholeFile() async throws {
        try await withTempDir { dir in
            let (db, root, wav, cue) = try setUp(dir)
            _ = try await Scanner(database: db).scan(rootID: root.id) { _ in }
            let tracks = try CollectionsStore(database: db).tracks(under: root.url.path)
            #expect(tracks.map(\.title).sorted() == ["Abertura", "Final"])
            #expect(tracks.allSatisfy { $0.mediaPath == wav.standardizedFileURL.path && $0.url.path == wav.standardizedFileURL.path })
            let final = try #require(tracks.first { $0.title == "Final" })
            #expect(final.start == 2 && final.end == nil && final.artist == "Banda" && final.album == "Ao Vivo")
            #expect(final.path == cue.standardizedFileURL.path + "#2")
            let busca = try await SearchService(database: db).search("abertura", limit: 10)
            #expect(busca.map(\.title) == ["Abertura"])

            // Nova varredura sem mudanças: mesmas faixas, sem duplicar.
            _ = try await Scanner(database: db).scan(rootID: root.id) { _ in }
            let again = try CollectionsStore(database: db).tracks(under: root.url.path)
            #expect(again.map(\.id).sorted() == tracks.map(\.id).sorted())

            // CUE apagado: as faixas saem e o arquivo inteiro volta a aparecer.
            try FileManager.default.removeItem(at: cue)
            _ = try await Scanner(database: db).scan(rootID: root.id) { _ in }
            let after = try CollectionsStore(database: db).tracks(under: root.url.path)
            #expect(after.count == 1 && after[0].path == wav.standardizedFileURL.path && after[0].mediaPath == nil)
        }
    }
}
