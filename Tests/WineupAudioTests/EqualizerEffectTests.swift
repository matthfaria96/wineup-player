import Testing
@testable import WineupAudio

@Suite struct EqualizerEffectTests {
    private func level(freq: Double, _ configure: @escaping (EffectChain) -> Void) throws -> Float {
        let out = try OfflineRender.render(.sine(freq: freq, amplitude: 0.25, channels: 2), configure: configure)
        return OfflineRender.rmsDB(out[0])
    }

    @Test func eachBandBoostsAndCutsTwelveDB() throws {
        for (i, f) in EffectChain.bandFrequencies.enumerated() {
            let flat = try level(freq: Double(f)) { _ in }
            for target: Float in [12, -12] {
                let v = try level(freq: Double(f)) { c in
                    var bands = [Float](repeating: 0, count: 10); bands[i] = target
                    c.applyEqualizer(globalGain: 0, bands: bands, bypass: false)
                }
                #expect(abs((v - flat) - target) < 0.3, "banda \(i) alvo \(target) obteve \(v - flat)")
            }
        }
    }

    @Test func preampLowersSixDB() throws {
        let flat = try level(freq: 1000) { _ in }
        let v = try level(freq: 1000) { $0.applyEqualizer(globalGain: -6, bands: [], bypass: false) }
        #expect(abs((v - flat) + 6) < 0.3)
    }

    @Test func bypassIgnoresBands() throws {
        let flat = try level(freq: 1000) { _ in }
        let v = try level(freq: 1000) {
            $0.applyEqualizer(globalGain: 0, bands: [Float](repeating: 12, count: 10), bypass: true)
        }
        #expect(abs(v - flat) < 0.3)
    }

    @Test func bassBoostRaisesLowEnergy() throws {
        let flat = try OfflineRender.render(.whiteNoise(amplitude: 0.2), seconds: 2)
        let boosted = try OfflineRender.render(.whiteNoise(amplitude: 0.2), seconds: 2) {
            $0.applyEqualizer(globalGain: 0, bands: [8, 6, 4, 2, 0, 0, 0, 0, 0, 0], bypass: false)
        }
        let a = OfflineRender.bandEnergyDB(samples: flat[0], low: 40, high: 200, sampleRate: 44_100)
        let b = OfflineRender.bandEnergyDB(samples: boosted[0], low: 40, high: 200, sampleRate: 44_100)
        #expect(b - a > 5)
    }
}
