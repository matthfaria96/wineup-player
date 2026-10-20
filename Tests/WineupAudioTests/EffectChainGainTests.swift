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
}
