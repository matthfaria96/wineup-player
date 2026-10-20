import AVFoundation
import Testing
@testable import WineupAudio

@Suite struct LevelTapTests {
    private func filled(_ value: (Int) -> Float, channels: Int = 2) -> AVAudioPCMBuffer {
        let fmt = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: AVAudioChannelCount(channels))!
        let buf = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: 1024)!
        buf.frameLength = 1024
        for c in 0..<channels { for i in 0..<1024 { buf.floatChannelData![c][i] = value(i) } }
        return buf
    }

    @Test func snapshotIsNilBeforeAnyBuffer() {
        #expect(LevelTap().snapshot() == nil)
    }

    @Test func sineGivesRealRmsAndPeak() throws {
        let tap = LevelTap()
        // 1 kHz com 44100/1000 nao inteiro; usa 1024 amostras de uma frequencia com ciclos inteiros: 43 ciclos.
        tap.process(buffer: filled { 0.5 * Float(sin(2 * .pi * 43 * Double($0) / 1024)) })
        let s = try #require(tap.snapshot())
        for c in 0..<2 {
            let db = 20 * log10(s.rms[c])
            #expect(abs(db - -9.03) < 0.5)
            #expect(abs(s.peak[c] - 0.5) < 0.02)
        }
        #expect(s.samples.count == 1024)
        #expect(s.sampleRate == 44_100)
        #expect(abs(s.samples[10]) > 0)
    }

    @Test func silenceGivesZeros() throws {
        let tap = LevelTap()
        tap.process(buffer: filled({ _ in 0 }))
        let s = try #require(tap.snapshot())
        #expect(s.rms == [0, 0] && s.peak == [0, 0])
    }

    @Test func installTwiceDoesNotThrow() throws {
        let engine = AVAudioEngine()
        let tap = LevelTap()
        tap.install(on: engine.mainMixerNode)
        tap.install(on: engine.mainMixerNode)
        tap.remove()
    }

    @Test func tapFiresDuringOfflineRender() throws {
        let tap = LevelTap()
        _ = try OfflineRender.render(.sine(freq: 1000, amplitude: 0.5, channels: 2)) { _ in } engineHook: {
            tap.install(on: $0.mainMixerNode)
        }
        // Se o tap nao disparar em render manual, o teste direto acima cobre a medicao.
        let s = try #require(tap.snapshot(), "tap deve disparar em render manual")
        #expect(s.peak[0] > 0.3)
        tap.remove()
    }
}
