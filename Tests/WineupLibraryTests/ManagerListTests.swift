import Foundation
import Testing
@testable import WineupLibrary

@Suite("Lista do gerenciador de metadados")
struct ManagerListTests {
    @Test func rowIndexFindsPositionsInOrder() {
        let index = RowIndex(["/a", "/b", "/c", "/b"])
        #expect(index["/a"] == 0)
        #expect(index["/b"] == 1)
        #expect(index["/x"] == nil)
        #expect(index.positions(of: Set(["/c", "/a", "/x"])) == [0, 2])
        #expect(index.count == 3)
    }

    @Test func searchKeyMatchesAnyFieldButNotAcrossFields() {
        let key = ManagerSearch.key(["01 Faixa.mp3", "Canção Nova", "Zé & Cia", "Álbum"])
        #expect(ManagerSearch.matches(key: key, query: ""))
        #expect(ManagerSearch.matches(key: key, query: TextMatch.normalize("cancao")))
        #expect(ManagerSearch.matches(key: key, query: TextMatch.normalize("ze and cia")))
        #expect(ManagerSearch.matches(key: key, query: TextMatch.normalize("album")))
        // "nova ze" só existiria juntando título e artista.
        #expect(!ManagerSearch.matches(key: key, query: TextMatch.normalize("nova ze")))
    }

    @Test func editsKeepTrailingSpaceWhileTypingAndTrimOnCommit() {
        // Digitando "Foo Bar" sobre "Foo": o espaço do meio não some.
        #expect(ManagerEdits.stored("Foo ", original: "Foo") == "Foo ")
        #expect(ManagerEdits.stored("Foo", original: "Foo") == nil)
        let original: (String) -> String = { ["title": "Foo", "artist": "A"][$0] ?? "" }
        let committed = ManagerEdits.committed(["title": "Foo ", "artist": " B ", "album": "  "], original: original)
        #expect(committed == ["artist": "B"])
    }

    @Test func issueCountsInOnePass() {
        let counts = IssueCounts.count([[FixerIssue.missingCover, .missingLyrics], [.missingCover], []])
        #expect(counts[.missingCover] == 2)
        #expect(counts[.missingLyrics] == 1)
        #expect(counts[.duplicate] == nil)
    }

    @Test func ignoredIssuesBatchWritesOnceAndClearsEmpty() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = IgnoredIssuesStore(directory: dir)
        try store.set(["/m/keep.mp3": [.missingYear]])
        try store.set(["/m/a.mp3": [.missingLyrics], "/m/b.mp3": [.missingCover, .missingGenre], "/m/keep.mp3": []])
        let all = IgnoredIssuesStore(directory: dir).all()
        #expect(all["/m/a.mp3"] == [.missingLyrics])
        #expect(all["/m/b.mp3"] == [.missingCover, .missingGenre])
        #expect(all["/m/keep.mp3"] == nil)
        try store.set([:])
        #expect(store.all().count == 2)
    }

    @Test func analyzeKeepsOrderWithCappedConcurrency() async {
        let urls = (0..<9).map { URL(fileURLWithPath: "/nao/existe/faixa \($0).mp3") }
        let files = await FolderAnalyzer.analyze(urls, concurrency: 2)
        #expect(files.map(\.url) == urls)
    }

    @Test func fingerprintOutputParses() throws {
        let json = Data(#"{"duration": 201.4, "fingerprint": "AQAB"}"#.utf8)
        #expect(try AcoustIDClient.parseFingerprint(json, status: 0) == .init(duration: 201, value: "AQAB"))
        #expect(try AcoustIDClient.parseFingerprint(json, status: 1) == nil)
    }
}
