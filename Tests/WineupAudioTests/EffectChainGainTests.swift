import Testing
@testable import WineupAudio

@Suite struct EffectChainGainTests {
    private func level(_ gain: Float?) throws -> Float {
        let out = try OfflineRender.render(.sine(freq: 1000, amplitude: 0.25, channels: 2)) { c in
            if let gain { c.setGain(linear: gain) }
        }
        return OfflineRender.rmsDB(out[0])
    }

    @Test func doubleGainIsSixDB() throws {
        let base = try level(nil)
        #expect(abs((try level(2.0) - base) - 6.02) < 0.2)
    }

    @Test func halfGainIsMinusSixDB() throws {
        let base = try level(nil)
        #expect(abs((try level(0.5) - base) + 6.02) < 0.2)
    }

    @Test func nanGainBecomesUnity() {
        let chain = EffectChain()
        chain.setGain(linear: .nan)
        #expect(chain.balance.outputVolume == 1.0)
        chain.setGain(linear: 100)
        #expect(chain.balance.outputVolume == 8.0)
    }

    /// Ganho que passaria de 0 dBFS: com o limitador, o pico fica abaixo de 1 (sem estourar); sem ele, passa.
    @Test func limiterHoldsPeaksBelowFullScale() throws {
        func peak(limited: Bool) throws -> Float {
            let out = try OfflineRender.render(.sine(freq: 1000, amplitude: 0.5, channels: 2), seconds: 2) { c in
                c.setGain(linear: 3)
                c.setLimiter(on: limited)
            }
            return out[0].suffix(44_100).map(abs).max() ?? 0
        }
        #expect(try peak(limited: false) > 1.2)
        #expect(try peak(limited: true) <= 1.0)
    }
}
