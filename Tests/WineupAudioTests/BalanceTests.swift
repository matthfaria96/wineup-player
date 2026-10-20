import Testing
@testable import WineupAudio

@Suite struct BalanceTests {
    private func run(channels: Int, pan: Float) throws -> (Float, Float) {
        let out = try OfflineRender.render(.sine(freq: 1000, amplitude: 0.5, channels: channels)) { $0.setPan(pan) }
        return (OfflineRender.rmsDB(out[0]), OfflineRender.rmsDB(out[1]))
    }

    @Test(arguments: [1, 2]) func panHardLeft(channels: Int) throws {
        let (l, r) = try run(channels: channels, pan: -1)
        #expect(abs(l - -9.03) < 0.5)
        #expect(r < -60)
    }

    @Test(arguments: [1, 2]) func panHardRight(channels: Int) throws {
        let (l, r) = try run(channels: channels, pan: 1)
        #expect(abs(r - -9.03) < 0.5)
        #expect(l < -60)
    }

    @Test func centerStereoKeepsBoth() throws {
        let (l, r) = try run(channels: 2, pan: 0)
        #expect(abs(l - -9.03) < 0.5 && abs(r - -9.03) < 0.5)
    }
}
