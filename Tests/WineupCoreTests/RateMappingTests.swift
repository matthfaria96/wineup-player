import Testing
@testable import WineupCore

@Test func sliderMapsToRate() {
    #expect(RateMapping.rate(slider: 0) == 0.5)
    #expect(abs(RateMapping.rate(slider: 0.5) - 1.0) < 1e-9)
    #expect(abs(RateMapping.rate(slider: 1) - 2.0) < 1e-9)
    #expect(RateMapping.rate(slider: 5) == RateMapping.rate(slider: 1))
}

@Test func rateInverse() {
    for s in [0.0, 0.25, 0.5, 0.8, 1] {
        #expect(abs(RateMapping.slider(rate: RateMapping.rate(slider: s)) - s) < 1e-9)
    }
}

@Test func remainingWall() {
    #expect(abs(RateMapping.remainingWallSeconds(total: 100, current: 40, rate: 1.5) - 40) < 1e-9)
    #expect(RateMapping.remainingWallSeconds(total: 10, current: 20, rate: 1) == 0)
    #expect(RateMapping.remainingWallSeconds(total: 10, current: 0, rate: 0) == 10)
}

@Test func panMapping() {
    #expect(RateMapping.pan(balance: 0) == -1)
    #expect(RateMapping.pan(balance: 0.5) == 0)
    #expect(RateMapping.pan(balance: 1) == 1)
}
