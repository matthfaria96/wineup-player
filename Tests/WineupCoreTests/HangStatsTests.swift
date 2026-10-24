import Testing
@testable import WineupCore

@Suite("Resumo das travadas")
struct HangStatsTests {
    @Test func emptyStepHasZeros() {
        let stats = HangStats([])
        #expect(stats == HangStats([]))
        #expect(stats.count == 0 && stats.worst == 0 && stats.total == 0)
    }

    @Test func countsWorstAndTotal() {
        let stats = HangStats([120, 80, 300])
        #expect(stats.count == 3)
        #expect(stats.worst == 300)
        #expect(stats.total == 500)
    }

    @Test func groupsByStepKeepingStepsWithoutHangs() {
        let events = [HangEvent(step: "a", milliseconds: 100), HangEvent(step: "b", milliseconds: 90),
                      HangEvent(step: "a", milliseconds: 200)]
        let stats = HangStats.byStep(events, steps: ["a", "b", "c"])
        #expect(stats["a"] == HangStats([100, 200]))
        #expect(stats["b"]?.count == 1)
        #expect(stats["c"] == HangStats([]))
    }

    @Test func reportLineIsTabSeparated() {
        let line = StressReport.line(step: "Músicas", duration: 1234.4, stats: HangStats([100, 250]))
        #expect(line == "Músicas\t1234\t250\t2\t350")
    }
}
