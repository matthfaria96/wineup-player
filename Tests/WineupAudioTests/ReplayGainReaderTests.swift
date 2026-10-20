import CryptoKit
import Foundation
import SFBAudioEngine
import Testing
@testable import WineupAudio

@Suite struct ReplayGainReaderTests {
    private func writeWAV(_ url: URL, seconds: Double = 0.3) throws {
        let rate = 44_100, frames = Int(Double(rate) * seconds)
        var pcm = Data()
        for i in 0..<frames {
            let v = Int16(8000 * sin(2 * Double.pi * 440 * Double(i) / Double(rate)))
            for _ in 0..<2 { withUnsafeBytes(of: v.littleEndian) { pcm.append(contentsOf: $0) } }
        }
        func le32(_ v: Int) -> Data { withUnsafeBytes(of: UInt32(v).littleEndian) { Data($0) } }
        func le16(_ v: Int) -> Data { withUnsafeBytes(of: UInt16(v).littleEndian) { Data($0) } }
        var d = Data("RIFF".utf8) + le32(36 + pcm.count) + Data("WAVEfmt ".utf8) + le32(16)
        d += le16(1) + le16(2) + le32(rate) + le32(rate * 4) + le16(4) + le16(16)
        d += Data("data".utf8) + le32(pcm.count) + pcm
        try d.write(to: url)
    }

    private func sha(_ url: URL) throws -> String {
        SHA256.hash(data: try Data(contentsOf: url)).map { String(format: "%02x", $0) }.joined()
    }

    @Test func readsReplayGainWithoutModifyingFile() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("WineupRG-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let wav = dir.appendingPathComponent("src.wav")
        let flac = dir.appendingPathComponent("a.flac")
        try writeWAV(wav)
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/afconvert")
        p.arguments = ["-f", "flac", "-d", "flac", wav.path, flac.path]
        try p.run(); p.waitUntilExit()
        #expect(p.terminationStatus == 0)

        let file = try AudioFile(url: flac)
        try file.readPropertiesAndMetadata()
        file.metadata.replayGainTrackGain = -6.5
        file.metadata.replayGainTrackPeak = 0.97
        file.metadata.replayGainAlbumGain = 3.25
        file.metadata.replayGainAlbumPeak = 0.5
        try file.writeMetadata()

        let before = try sha(flac)
        let info = ReplayGainReader.read(flac)
        #expect(info.trackGain == -6.5)
        #expect(info.trackPeak == 0.97)
        #expect(info.albumGain == 3.25)
        #expect(info.albumPeak == 0.5)
        #expect(try sha(flac) == before)
    }

    @Test func missingFileYieldsEmptyInfo() {
        let info = ReplayGainReader.read(URL(fileURLWithPath: "/nonexistent/x.flac"))
        #expect(info.trackGain == nil && info.albumGain == nil)
    }
}
