import AVFoundation
import Foundation
import Testing
@testable import WineupAudio
import WineupCore

@Suite("Forma de onda real")
struct WaveformAnalyzerTests {
    /// 4 s: 2 s baixos (−30 dBFS) e 2 s altos (−6 dBFS).
    private func quietThenLoud(_ dir: URL) throws -> URL {
        let url = dir.appendingPathComponent("quiet-loud.wav")
        let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 2)!
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        let frames: AVAudioFrameCount = 44_100 * 4
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buffer.frameLength = frames
        for c in 0..<2 {
            for i in 0..<Int(frames) {
                let amp: Float = i < Int(frames) / 2 ? 0.0447 : 0.707   // picos −27 e −3 dBFS: RMS −30 e −6
                buffer.floatChannelData![c][i] = amp * Float(sin(2 * .pi * 110 * Double(i) / 44_100))
            }
        }
        try file.write(from: buffer)
        return url
    }

    @Test func loudPartIsTallerThanQuietPart() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let levels = try #require(WaveformAnalyzer().levels(try quietThenLoud(dir)))
        #expect(levels.count == WaveformAnalyzer.bucketCount)
        let first = levels[WaveformAnalyzer.bucketCount / 4], last = levels[WaveformAnalyzer.bucketCount * 3 / 4]
        #expect(abs(first - -30) < 1.5 && abs(last - -6) < 1.5)    // RMS de seno = pico − 3 dB
        let h = Waveform.heights(levels)
        #expect(h[WaveformAnalyzer.bucketCount * 3 / 4] > h[WaveformAnalyzer.bucketCount / 4] + 0.4)
    }
}

/// Conferência manual com uma música de verdade: `WINEUP_WAVEFORM_FILE=<arquivo> scripts/test.sh --filter WaveformReal`.
@Suite("Forma de onda: música real", .enabled(if: ProcessInfo.processInfo.environment["WINEUP_WAVEFORM_FILE"] != nil))
struct WaveformRealTests {
    @Test func printsShapeAndTiming() throws {
        let url = URL(fileURLWithPath: ProcessInfo.processInfo.environment["WINEUP_WAVEFORM_FILE"]!)
        let start = Date()
        let levels = try #require(WaveformAnalyzer().levels(url))
        let elapsed = Date().timeIntervalSince(start)
        let blocks = Array(" ▁▂▃▄▅▆▇█")
        print("WAVEFORM \(url.lastPathComponent) \(String(format: "%.2f", elapsed)) s")
        for span: Float in [BarMeter.spanDB] {
            let h = Waveform.heights(levels, spanDB: span)
            let line = stride(from: 0, to: h.count, by: 6).map { i in blocks[min(8, Int(h[i...min(i + 5, h.count - 1)].max()! * 8.99))] }
            print("span \(Int(span)) " + String(line))
        }
    }
}
