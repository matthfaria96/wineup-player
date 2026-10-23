import Foundation
import Testing
@testable import WineupLibrary

/// Respostas prontas por trecho de URL; registra o que foi pedido.
final class StubFetcher: HTTPFetching, @unchecked Sendable {
    private let routes: [(String, Int, Data)]
    private let lock = NSLock()
    private(set) var requested: [URL] = []

    init(_ routes: [(String, Int, String)]) { self.routes = routes.map { ($0.0, $0.1, Data($0.2.utf8)) } }

    func get(_ url: URL, headers: [String: String]) async throws -> (Data, Int) {
        lock.withLock { requested.append(url) }
        let s = url.absoluteString.removingPercentEncoding ?? url.absoluteString
        guard let hit = routes.first(where: { s.contains($0.0) }) else { return (Data(), 404) }
        return (hit.2, hit.1)
    }
}

private let mbSearch = """
{"recordings":[
 {"id":"rec-1","score":100,"title":"All Melody","length":553000,
  "artist-credit":[{"name":"Nils Frahm","joinphrase":""}],
  "releases":[
   {"id":"rel-comp","title":"Best of Piano","status":"Official","date":"2020",
    "release-group":{"id":"rg-comp","primary-type":"Album","secondary-types":["Compilation"]},
    "media":[{"position":1,"track":[{"number":"3"}]}]},
   {"id":"rel-1","title":"All Melody","status":"Official","date":"2018-01-26",
    "artist-credit":[{"name":"Nils Frahm","joinphrase":""}],
    "release-group":{"id":"rg-1","primary-type":"Album"},
    "media":[{"position":1,"track":[{"number":"7"}]}]}],
  "tags":[{"count":3,"name":"modern classical"},{"count":1,"name":"ambient"}]},
 {"id":"rec-2","score":60,"title":"Melody","length":200000,
  "artist-credit":[{"name":"Someone Else","joinphrase":""}],"releases":[]}
]}
"""

@Suite("Gerenciador de metadados: busca e correspondência")
struct FixerLogicTests {
    @Test func similarityIgnoresAccentsCaseAndFeat() {
        #expect(TextMatch.similarity("Ação feat. X", "acao") == 1)
        #expect(TextMatch.similarity("Simon & Garfunkel", "Simon and Garfunkel") == 1)
        #expect(TextMatch.similarity("abc", "xyz") < 0.4)
    }

    @Test func filenameGuess() {
        let g = FilenameGuess.parse(URL(fileURLWithPath: "/m/07 - Nils Frahm - All Melody.mp3"))
        #expect(g == FilenameGuess(artist: "Nils Frahm", title: "All Melody", trackNumber: 7))
        #expect(FilenameGuess.parse(URL(fileURLWithPath: "/m/08 #2.mp3")).title == "#2")
        #expect(FilenameGuess.parse(URL(fileURLWithPath: "/m/1999.mp3")).title == "1999")
    }

    @Test func musicBrainzSearchPicksStudioAlbumAndScores() async throws {
        let stub = StubFetcher([("musicbrainz.org/ws/2/recording", 200, mbSearch)])
        let mb = MusicBrainzClient(fetcher: stub, minimumInterval: 0)
        let list = try await mb.search(title: "All Melody", artist: "Nils Frahm", album: nil, duration: 552)
        let best = try #require(list.first)
        #expect(best.recordingID == "rec-1")
        #expect(best.album == "All Melody" && best.year == "2018" && best.trackNumber == 7)
        #expect(best.genre == "Modern classical")
        #expect(best.confidence > 0.95)
        #expect(list.last!.confidence < 0.6)
        #expect(stub.requested.first?.absoluteString.contains("fmt=json") == true)
    }

    @Test func preferredAlbumWinsOverStudioRule() {
        let r = MusicBrainzClient.bestRelease(
            [["id": "a", "title": "All Melody", "status": "Official", "release-group": ["primary-type": "Album"]],
             ["id": "b", "title": "Best of Piano", "status": "Official"]], preferAlbum: "best of piano")
        #expect(r?["id"] as? String == "b")
    }

    @Test func fillPolicy() {
        let file = FixerFile(url: URL(fileURLWithPath: "/m/a.mp3"), fields: ["title": "All melody", "artist": "Nils Frahm"])
        let m = MatchCandidate(source: .musicBrainz, recordingID: "r", title: "All Melody", artist: "Nils Frahm",
                               album: "All Melody", year: "2018")
        #expect(MetadataFixer.fieldChanges(m, file: file, policy: .missingOnly) == ["album": "All Melody", "year": "2018"])
        #expect(MetadataFixer.fieldChanges(m, file: file, policy: .overwrite)["title"] == "All Melody")
    }

    @Test func lrclibExactThenSearchFallback() async throws {
        let stub = StubFetcher([
            ("lrclib.net/api/get", 404, "{}"),
            ("lrclib.net/api/search", 200, """
            [{"id":1,"trackName":"All Melody","artistName":"Nils Frahm","duration":600,"plainLyrics":"far"},
             {"id":2,"trackName":"All Melody","artistName":"Nils Frahm","duration":553,
              "syncedLyrics":"[00:01.00] hi","plainLyrics":"hi"}]
            """)])
        let client = LRCLibClient(fetcher: stub)
        let best = try await client.best(title: "All Melody", artist: "Nils Frahm", album: nil, duration: 552)
        #expect(best?.id == "lrclib:2" && best?.isSynced == true)
        #expect(best?.text == "[00:01.00] hi")
    }

    @Test func coverArtFallsBackToReleaseGroupAndChecksBytes() async throws {
        let png = String(decoding: tinyPNG, as: UTF8.self)
        _ = png
        let stub = StubFetcher([("release/rel-1/front", 404, ""), ("release/rel-x/front", 200, "<html>")])
        let client = CoverArtClient(fetcher: stub)
        #expect(try await client.frontCover(releaseID: "rel-x", releaseGroupID: nil) == nil)
        #expect(try await client.frontCover(releaseID: "rel-1", releaseGroupID: "rg-1") == nil)
        #expect(stub.requested.map(\.absoluteString).contains { $0.contains("release-group/rg-1") })
        #expect(CoverArtClient.mimeType(of: tinyPNG) == "image/png")
    }

    @Test func acoustIDParse() {
        let list = AcoustIDClient.parse(["status": "ok", "results": [
            ["score": 0.5, "recordings": [["id": "b"]]],
            ["score": 0.97, "recordings": [["id": "a"], ["id": "b"]]]]])
        #expect(list.map(\.recordingID) == ["a", "b"])
        #expect(AcoustIDClient.parse(["status": "error"]).isEmpty)
    }

    @Test func duplicatesNeedSameSongAndCloseDuration() {
        func f(_ name: String, _ title: String, _ d: Double) -> FixerFile {
            FixerFile(url: URL(fileURLWithPath: "/m/\(name)"), fields: ["title": title, "artist": "A"], duration: d)
        }
        let out = FolderAnalyzer.markDuplicates([f("1.mp3", "Song", 200), f("2.flac", "song", 201.5),
                                                 f("3.mp3", "Song", 260), f("4.mp3", "Other", 200)])
        #expect(out[0].duplicateGroup != nil && out[0].duplicateGroup == out[1].duplicateGroup)
        #expect(out[2].duplicateGroup == nil && out[3].duplicateGroup == nil)
        #expect(out[1].issues.contains(.duplicate))
    }

    @Test func proposeUsesFilenameWhenTagsMissing() async throws {
        let stub = StubFetcher([
            ("musicbrainz.org", 200, mbSearch),
            ("coverartarchive.org/release/rel-1/front", 200, String(decoding: tinyPNG, as: UTF8.self)),
            ("lrclib.net/api/get", 200, #"{"id":9,"trackName":"All Melody","artistName":"Nils Frahm","syncedLyrics":"[00:01.00] a"}"#)])
        let fixer = MetadataFixer(musicBrainz: MusicBrainzClient(fetcher: stub, minimumInterval: 0),
                                  covers: CoverArtClient(fetcher: stub), lyrics: LyricsService(primary: LRCLibClient(fetcher: stub), backup: nil), fpcalc: nil)
        let file = FixerFile(url: URL(fileURLWithPath: "/m/07 - Nils Frahm - All Melody.mp3"), duration: 553)
        let p = try await fixer.propose(for: file)
        #expect(p.match?.recordingID == "rec-1")
        #expect(p.lyrics?.id == "lrclib:9")
        let mbURL = try #require(stub.requested.first { $0.host == "musicbrainz.org" })
        #expect(mbURL.absoluteString.removingPercentEncoding!.contains("artist:\"Nils Frahm\""))
    }
}

@Suite("Gerenciador de metadados: versão de estúdio")
struct FixerReleaseRankTests {
    @Test func studioRecordingBeatsLiveBootlegWithSameTitle() async throws {
        let json = """
        {"recordings":[
         {"id":"live","title":"Karma Police","artist-credit":[{"name":"Radiohead"}],
          "releases":[{"id":"boot","title":"2001-09-29: Oxford","status":"Bootleg",
            "release-group":{"primary-type":"Album","secondary-types":["Live"]}}]},
         {"id":"studio","title":"Karma Police","artist-credit":[{"name":"Radiohead"}],
          "releases":[{"id":"okc","title":"OK Computer","status":"Official","date":"1997-05-21",
            "release-group":{"id":"rg","primary-type":"Album"},"media":[{"position":1,"track":[{"number":"6"}]}]}]}
        ]}
        """
        let mb = MusicBrainzClient(fetcher: StubFetcher([("musicbrainz.org", 200, json)]), minimumInterval: 0)
        let list = try await mb.search(title: "Karma Police", artist: "Radiohead", album: nil, duration: nil)
        #expect(list.first?.album == "OK Computer")
        #expect(list.first?.trackNumber == 6)
        #expect(list.last!.confidence < list.first!.confidence)
    }
}

@Suite("Gerenciador de metadados: confiança")
struct FixerConfidenceTests {
    @Test func missingCandidateDurationIsNotAnAdvantage() {
        let withLength = TextMatch.confidence(title: "A", artist: "B", duration: 30, candidateTitle: "A",
                                              candidateArtist: "B", candidateDuration: 264)
        let without = TextMatch.confidence(title: "A", artist: "B", duration: 30, candidateTitle: "A",
                                           candidateArtist: "B", candidateDuration: nil)
        let exact = TextMatch.confidence(title: "A", artist: "B", duration: 264, candidateTitle: "A",
                                         candidateArtist: "B", candidateDuration: 265)
        #expect(without < exact && without > withLength && exact == 1)
    }
}

@Suite("Gerenciador de metadados: dica de álbum")
struct ITunesHintTests {
    @Test func prefersArtistAlbumOverCompilationAndCleansEdition() {
        let results: [[String: Any]] = [
            ["trackName": "Karma Police", "artistName": "Radiohead", "collectionName": "Now 97",
             "collectionArtistName": "Various Artists", "trackTimeMillis": 264000.0],
            ["trackName": "Karma Police", "artistName": "Radiohead", "collectionName": "OK Computer (Remastered)",
             "trackTimeMillis": 264000.0, "primaryGenreName": "Alternative"]]
        let hint = ITunesHintClient.best(results, title: "Karma Police", artist: "Radiohead", duration: 264)
        #expect(hint == ITunesHintClient.Hint(album: "OK Computer", genre: "Alternative"))
        #expect(ITunesHintClient.best(results, title: "Paranoid Android", artist: "Radiohead", duration: nil) == nil)
    }
}

@Suite("Gerenciador de metadados: edição original")
struct OriginalEditionTests {
    @Test func sameAlbumNamePicksOldestOfficial() {
        let r = MusicBrainzClient.bestRelease(
            [["id": "2009", "title": "OK Computer", "status": "Official", "date": "2009-03-24",
              "release-group": ["primary-type": "Album"]],
             ["id": "1997", "title": "OK Computer", "status": "Official", "date": "1997-05-21",
              "release-group": ["primary-type": "Album"]]], preferAlbum: "OK Computer")
        #expect(r?["id"] as? String == "1997")
    }
}
