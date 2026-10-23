import Foundation
import ShazamKit
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

@Suite("Shazam")
struct ShazamTests {
    @Test func excerptDecodesAnyFormatTo44kMono() async throws {
        try await withTempDir { dir in
            let url = try FormatCase.flac.make(dir)
            let buffer = try #require(try AudioExcerpt.read(url, seconds: 1))
            #expect(buffer.format.sampleRate == 44_100 && buffer.format.channelCount == 1)
            #expect(buffer.frameLength > 0)
        }
    }

    @Test func entitlementErrorIsRecognised() {
        #expect(ShazamRecognizer.isEntitlementError(NSError(domain: SHErrorDomain, code: 202)))
        #expect(ShazamRecognizer.isEntitlementError(NSError(domain: "com.apple.ShazamCore", code: 102, userInfo: [
            NSDebugDescriptionErrorKey: "Please check that you have enabled the ShazamKit App Service for this app identifier"])))
        #expect(!ShazamRecognizer.isEntitlementError(NSError(domain: SHErrorDomain, code: 201)))
    }
}
