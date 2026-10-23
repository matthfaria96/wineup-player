import Foundation
import Testing
@testable import WineupCore

@Suite("Correção de Som: medidor EBU R128")
struct LoudnessTests {
    private func measure(amplitude: Float, frequency: Double = 997, seconds: Double = 5,
                         rate: Double = 48_000, channels: Int = 2) -> (Double?, Double) {
        var meter = LoudnessMeter(sampleRate: rate, channels: channels)
        let n = Int(rate * seconds)
        let samples = (0..<n).map { amplitude * Float(sin(2 * .pi * frequency * Double($0) / rate)) }
        samples.withUnsafeBufferPointer { p in meter.process(Array(repeating: p, count: channels)) }
        return (meter.integrated(), meter.peak)
    }

    @Test func calibrationSineMatchesStandard() {
        // BS.1770: seno de 997 Hz a 0 dBFS num canal = -3,01 LUFS; nos dois canais = 0 LUFS.
        let mono = measure(amplitude: 1, channels: 1).0!
        #expect(abs(mono - -3.01) < 0.1)
        let stereo = measure(amplitude: 0.1, channels: 2).0!
        #expect(abs(stereo - -20) < 0.1)
        #expect(abs(measure(amplitude: 0.1, rate: 44_100).0! - -20) < 0.1)
    }

    @Test func silenceHasNoLoudness() {
        #expect(measure(amplitude: 0).0 == nil)
    }

    @Test func gainBringsTrackToTargetWithoutClipping() {
        let quiet = LoudnessInfo(integrated: -24, peak: 0.2)
        #expect(abs(20 * log10(SoundCorrection.linearGain(target: -14, loudness: quiet)) - 10) < 0.01)
        let loud = LoudnessInfo(integrated: -6, peak: 1)
        #expect(abs(20 * log10(SoundCorrection.linearGain(target: -14, loudness: loud)) - -8) < 0.01)
        let peaky = LoudnessInfo(integrated: -24, peak: 0.9)
        #expect(SoundCorrection.linearGain(target: -14, loudness: peaky) * 0.9 <= 0.98 + 1e-9)
        #expect(SoundCorrection.estimate(from: ReplayGainInfo(trackGain: -6))?.integrated == -12)
    }
}
