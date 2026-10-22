import Foundation
import Testing
@testable import WineupCore

struct FormatParsersTests {
    @Test func lrcTimesAndOffset() throws {
        let lrc = try #require(LRCParser.parse("""
            [ar:Banda]
            [offset:500]
            [00:01.50]Primeira
            [00:10.00][00:20.00]Refrão
            [00:05:25]Segunda
            """))
        #expect(lrc.lines.map(\.text) == ["Primeira", "Segunda", "Refrão", "Refrão"])
        #expect(lrc.lines.map(\.time) == [1.0, 4.75, 9.5, 19.5])
        #expect(lrc.index(at: 0.5) == nil)
        #expect(lrc.index(at: 5) == 1)
        #expect(lrc.index(at: 100) == 3)
        #expect(LRCParser.parse("texto sem marcas") == nil)
    }

    @Test func m3uRelativeAbsoluteAndInfo() {
        let base = URL(fileURLWithPath: "/m/listas")
        let entries = M3U.parse("""
            #EXTM3U
            #EXTINF:215,Banda - Música
            ../rock/a.flac
            /abs/b.mp3
            file:///c%20d.ogg
            http://radio/stream
            sub\\e.m4a
            """, baseDirectory: base)
        #expect(entries.map(\.url.path) == ["/m/rock/a.flac", "/abs/b.mp3", "/c d.ogg", "/m/listas/sub/e.m4a"])
        #expect(entries[0].title == "Banda - Música" && entries[0].duration == 215)
        let track = Track(artist: "A", title: "T", duration: 10, mark: nil, url: URL(fileURLWithPath: "/x.flac"))
        #expect(M3U.write([track]) == "#EXTM3U\n#EXTINF:10,A - T\n/x.flac\n")
    }

    @Test func cueSheetTracks() throws {
        let cue = try #require(CueSheet.parse("""
            PERFORMER "Banda"
            TITLE "Ao Vivo"
            FILE "show.flac" WAVE
              TRACK 01 AUDIO
                TITLE "Abertura"
                INDEX 01 00:00:00
              TRACK 02 AUDIO
                TITLE "Segunda"
                PERFORMER "Convidado"
                INDEX 00 03:58:00
                INDEX 01 04:00:37
            """, baseDirectory: URL(fileURLWithPath: "/m")))
        #expect(cue.album == "Ao Vivo")
        #expect(cue.entries.count == 2)
        #expect(cue.entries[0].end == cue.entries[1].start)
        #expect(abs(cue.entries[1].start - 240.4933) < 0.001)
        #expect(cue.entries[1].performer == "Convidado" && cue.entries[0].performer == "Banda")
        #expect(cue.entries[1].end == nil && cue.entries[0].file.path == "/m/show.flac")
    }
}

struct R128GainTests {
    @Test func convertsQ78ToReplayGainReference() {
        #expect(R128Gain.replayGainDB(fromTag: "0") == 5)
        #expect(R128Gain.replayGainDB(fromTag: "-2560") == -5)       // -10 dB R128 → -5 dB RG
        #expect(R128Gain.replayGainDB(fromTag: " 512 ") == 7)
        #expect(R128Gain.replayGainDB(fromTag: "abc") == nil)
        #expect(R128Gain.replayGainDB(fromTag: "99999") == nil)
        #expect(R128Gain.lookup("R128_TRACK_GAIN", in: ["r128_track_gain": "-256"]) == "-256")
    }
}
