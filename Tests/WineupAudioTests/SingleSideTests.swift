import AVFoundation
import Testing
@testable import WineupAudio

/// L/R levam a música inteira (os dois canais somados) para um lado só.
@Suite struct SingleSideTests {
    private let stereo = AVAudioFormat(standardFormatWithSampleRate: OfflineRender.sampleRate, channels: 2)!

    private func run(side: Int) throws -> (Float, Float) {
        // Sinal só no canal esquerdo: em R ele precisa aparecer inteiro na direita.
        var chainRef: EffectChain?
        let out = try OfflineRender.render(.leftOnlySine(freq: 1000, amplitude: 0.5),
                                           configure: { chainRef = $0 },
                                           engineHook: { engine in
                                               chainRef?.setSide(side, engine: engine, format: stereo)
                                           })
        return (OfflineRender.rmsDB(out[0]), OfflineRender.rmsDB(out[1]))
    }

    @Test func rightCarriesTheWholeMusic() throws {
        let (l, r) = try run(side: 1)
        #expect(l < -60)
        #expect(r > -30)
    }

    @Test func leftCarriesTheWholeMusic() throws {
        let (l, r) = try run(side: -1)
        #expect(l > -30)
        #expect(r < -60)
    }

    @Test func normalKeepsOriginalStereo() throws {
        let (l, r) = try run(side: 0)
        #expect(l > -30)
        #expect(r < -60)
    }
}
