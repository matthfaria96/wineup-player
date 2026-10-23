import Foundation
import Testing
@testable import WineupLibrary

/// Rede de verdade: só com WINEUP_LIVE=1.
@Suite("Gerenciador de metadados: serviços reais", .enabled(if: ProcessInfo.processInfo.environment["WINEUP_LIVE"] == "1"))
struct FixerLiveTests {
    @Test func realLookup() async throws {
        let file = FixerFile(url: URL(fileURLWithPath: "/m/07 - Nils Frahm - All Melody.mp3"), duration: nil)
        let p = try await MetadataFixer(fpcalc: nil).propose(for: file)
        let m = try #require(p.match)
        print("match:", m.title, "|", m.artist, "|", m.album ?? "-", "|", m.year ?? "-", "| conf", m.confidence)
        for c in p.candidates.prefix(5) { print("  cand:", c.title, "|", c.album ?? "-", "|", c.year ?? "-", c.confidence) }
        print("cover bytes:", p.cover?.data.count ?? 0, "lyrics synced:", p.lyrics?.isSynced ?? false)
        #expect(m.confidence >= 0.8 && m.album != nil && p.cover != nil)
    }

    @Test func studioAlbumForWellKnownSong() async throws {
        try await Task.sleep(nanoseconds: 2_000_000_000)
        let file = FixerFile(url: URL(fileURLWithPath: "/m/Radiohead - Karma Police.flac"), duration: 264)
        let list = try await MetadataFixer(fpcalc: nil).findMatches(for: file)
        let m = try #require(list.first)
        print("karma:", m.album ?? "-", m.year ?? "-", m.trackNumber ?? 0, m.confidence)
        #expect(m.album == "OK Computer")
    }
}

@Suite("Shazam ao vivo", .enabled(if: ProcessInfo.processInfo.environment["WINEUP_SHAZAM_FILE"] != nil))
struct ShazamLiveTests {
    @Test func recognizeOrReportUnavailable() async throws {
        let url = URL(fileURLWithPath: ProcessInfo.processInfo.environment["WINEUP_SHAZAM_FILE"]!)
        let r = ShazamRecognizer()
        let heard = try await r.recognize(url)
        let state = await r.availability
        print("shazam:", heard.map { "\($0.title) | \($0.artist)" } ?? "nil", state)
        #expect(heard != nil || state != .unknown)
    }
}
