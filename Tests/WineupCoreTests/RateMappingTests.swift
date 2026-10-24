import Testing
@testable import WineupCore

@Test func remainingWall() {
    #expect(abs(RateMapping.remainingWallSeconds(total: 100, current: 40, rate: 1.5) - 40) < 1e-9)
    #expect(RateMapping.remainingWallSeconds(total: 10, current: 20, rate: 1) == 0)
    #expect(RateMapping.remainingWallSeconds(total: 10, current: 0, rate: 0) == 10)
}
