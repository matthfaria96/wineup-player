import AVFoundation
import Foundation
import Testing
@testable import WineupAudio
import WineupCore

@Suite("Correção de Som: medição de arquivos")
struct LoudnessAnalyzerTests {
    private func sineFile(_ dir: URL, amplitude: Float) throws -> URL {
        let url = dir.appendingPathComponent("sine-\(amplitude).wav")
        let format = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2)!
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        let frames: AVAudioFrameCount = 48_000 * 5
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buffer.frameLength = frames
        for c in 0..<2 {
            for i in 0..<Int(frames) { buffer.floatChannelData![c][i] = amplitude * Float(sin(2 * .pi * 997 * Double(i) / 48_000)) }
        }
        try file.write(from: buffer)
        return url
    }

    @Test func measuresFileAndCachesIt() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let analyzer = LoudnessAnalyzer(directory: dir)
        let url = try sineFile(dir, amplitude: 0.1)
        let info = try #require(analyzer.measure(url))
        #expect(abs(info.integrated - -20) < 0.2)
        #expect(abs(info.peak - 0.1) < 0.01)
        #expect(analyzer.cached(url) == info)
        Thread.sleep(forTimeInterval: 0.3)
        #expect(LoudnessAnalyzer(directory: dir).cached(url) == info)
    }
}

@Suite("Correção de Som: músicas reais", .enabled(if: ProcessInfo.processInfo.environment["WINEUP_LOUDNESS_DIR"] != nil))
struct LoudnessRealTests {
    @Test func measureFolder() throws {
        let dir = URL(fileURLWithPath: ProcessInfo.processInfo.environment["WINEUP_LOUDNESS_DIR"]!)
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let analyzer = LoudnessAnalyzer(directory: tmp)
        for f in try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
            .filter({ $0.pathExtension == "mp3" }).sorted(by: { $0.path < $1.path }).prefix(4) {
            let start = Date()
            let i = analyzer.measure(f)
            print("lufs:", f.lastPathComponent.prefix(40), String(format: "%.1f LUFS pico %.2f  ganho %+.1f dB  %.2fs", i?.integrated ?? .nan, i?.peak ?? 0,
                  20 * log10(SoundCorrection.linearGain(target: -14, loudness: i!)), Date().timeIntervalSince(start)))
        }
        try? FileManager.default.removeItem(at: tmp)
    }
}
