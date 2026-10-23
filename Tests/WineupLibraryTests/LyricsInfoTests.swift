import Foundation
import Testing
@testable import WineupLibrary

@Suite("Letras: sincronizada x estática")
struct LyricsInfoTests {
    @Test func syncedWithHeaderAndOffset() {
        let info = LyricsInfo("[ar:Radiohead]\n[ti:Karma Police]\n[offset:+500]\n[00:10.50] Karma police\n[00:14.00] Arrest this man\n")
        #expect(info.kind == .synced && info.isSynced)
        #expect(info.lines.count == 2 && info.lines[0].text == "Karma police")
        #expect(info.lines[0].time == 10.0)
        #expect(info.header["ar"] == "Radiohead" && info.header["ti"] == "Karma Police")
        #expect(info.activeIndex(at: 9) == nil && info.activeIndex(at: 12) == 0 && info.activeIndex(at: 99) == 1)
        #expect(info.summary.contains("2 linhas com marca de tempo"))
    }

    @Test func plainLyricsAreStatic() {
        let info = LyricsInfo("[ar:X]\n\nPrimeira linha\nSegunda\n\n")
        #expect(info.kind == .plain && !info.isSynced)
        #expect(info.lines.map(\.text) == ["Primeira linha", "Segunda"])
        #expect(info.activeIndex(at: 5) == nil)
        #expect(LyricsInfo("  \n").kind == .empty)
    }

    @Test func analyzerReportsLyricsKind() async throws {
        try await withTempDir { dir in
            let url = try FormatCase.flac.make(dir)
            _ = try LyricsFileWriter.write("só texto", for: url, replace: false)
            #expect(FolderAnalyzer.read(url).lyricsSynced == false)
            _ = try LyricsFileWriter.write("[00:01.00] tempo", for: url, replace: true)
            #expect(FolderAnalyzer.read(url).lyricsSynced == true)
        }
    }
}

@Suite("Letras: busca")
struct LyricsSearchTests {
    @Test func cleanTitleDropsEditionNotes() {
        #expect(TextMatch.cleanTitle("Karma Police (Remastered 2011)") == "Karma Police")
        #expect(TextMatch.cleanTitle("Paranoid Android - 2017 Remaster") == "Paranoid Android")
        #expect(TextMatch.cleanTitle("Song [Live at Wembley]") == "Song")
        #expect(TextMatch.cleanTitle("Love Me Do (feat. X)") == "Love Me Do")
        #expect(TextMatch.cleanTitle("Live and Let Die") == "Live and Let Die")
    }

    @Test func staticLyricsAskForSyncedVersion() async throws {
        let stub = StubFetcher([
            ("lrclib.net/api/get", 200, #"{"id":1,"trackName":"A","artistName":"B","plainLyrics":"só texto"}"#),
            ("lrclib.net/api/search", 200, #"[{"id":2,"trackName":"A","artistName":"B","duration":200,"syncedLyrics":"[00:01.00] x"}]"#)])
        let c = LRCLibClient(fetcher: stub)
        #expect(try await c.best(title: "A", artist: "B", album: nil, duration: 200)?.id == "lrclib:1")
        #expect(try await c.best(title: "A", artist: "B", album: nil, duration: 200, syncedOnly: true)?.id == "lrclib:2")
    }
}

@Suite("Letras: fontes de reserva")
struct LyricsFallbackTests {
    private let neteaseSearch = """
    {"result":{"songs":[{"id":17292978,"name":"Shut Me Up","artists":[{"name":"Mindless Self Indulgence"}],
      "album":{"name":"You'll Rebel To Anything"},"duration":168000},
      {"id":5,"name":"Outra","artists":[{"name":"X"}],"duration":100000}]}}
    """
    private let neteaseLyric = #"{"lrc":{"lyric":"[00:00.00] 作词 : James Euringer\n[00:00.00] 作曲 : James Euringer\n[00:12.51]The mic, the treble\n[00:13.95]I like my coffee black\n"}}"#

    @Test func netEaseIsUsedWhenPrimaryHasNothingAndCreditsAreRemoved() async throws {
        let stub = StubFetcher([
            ("lrclib.net/api/get", 404, "{}"), ("lrclib.net/api/search", 200, "[]"),
            ("music.163.com/api/search", 200, neteaseSearch), ("music.163.com/api/song/lyric", 200, neteaseLyric)])
        let service = LyricsService(primary: LRCLibClient(fetcher: stub), backup: NetEaseLyricsClient(fetcher: stub))
        let found = try #require(try await service.best(title: "Shut Me Up", artist: "Mindless Self Indulgence",
                                                        album: nil, duration: 168))
        #expect(found.id == "netease:17292978" && found.isSynced)
        #expect(found.synced?.contains("作词") == false)
        #expect(LyricsInfo(found.synced!).lines.first?.text == "The mic, the treble")
    }

    @Test func netEaseRejectsOtherSongs() {
        let s = NetEaseLyricsClient.Song(id: 1, title: "Mastermind", artist: "Mindless Self Indulgence", album: nil, duration: 179)
        #expect(!NetEaseLyricsClient.matches(s, title: "Shut Me Up", artist: "Mindless Self Indulgence", duration: 168))
    }

    @Test func musixmatchDecoyAnswerIsIgnored() throws {
        // Sem conta, o Musixmatch responde com outra música ("NOKIA"): não pode virar letra.
        let json: [String: Any] = ["message": ["header": ["status_code": 200], "body": ["macro_calls": [
            "matcher.track.get": ["message": ["body": ["track": ["track_name": "NOKIA", "artist_name": "Drake", "track_id": 1]]]],
            "track.subtitles.get": ["message": ["body": ["subtitle_list": [["subtitle": ["subtitle_body": "[00:12.00]Wob"]]]]]]]]]]
        #expect(try MusixmatchClient.parse(json, title: "Shut Me Up", artist: "Mindless Self Indulgence", duration: 168) == nil)
        let ok: [String: Any] = ["message": ["header": ["status_code": 200], "body": ["macro_calls": [
            "matcher.track.get": ["message": ["body": ["track": ["track_name": "Shut Me Up", "artist_name": "Mindless Self Indulgence",
                                                                  "track_id": 7, "track_length": 168]]]],
            "track.subtitles.get": ["message": ["body": ["subtitle_list": [["subtitle": ["subtitle_body": "[00:12.51]The mic"]]]]]]]]]]
        let found = try MusixmatchClient.parse(ok, title: "Shut Me Up", artist: "Mindless Self Indulgence", duration: 168)
        #expect(found?.id == "musixmatch:7" && found?.isSynced == true)
        let denied: [String: Any] = ["message": ["header": ["status_code": 401]]]
        #expect(throws: MusixmatchClient.Failure.invalidToken) {
            try MusixmatchClient.parse(denied, title: "A", artist: "B", duration: nil)
        }
    }
}
