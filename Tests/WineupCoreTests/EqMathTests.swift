import Testing
@testable import WineupCore

@Test func flatHasNoCompensation() {
    let flat = Array(repeating: 0.0, count: 10)
    #expect(EqMath.peakResponseDB(bands: flat) == 0)
    #expect(EqMath.effectiveGlobalGain(preamp: 0, bands: flat) == 0)
}

@Test func allMaxOverlapsAndCompensates() {
    let hot = Array(repeating: 12.0, count: 10)
    #expect(EqMath.peakResponseDB(bands: hot) >= 19)
    #expect(EqMath.effectiveGlobalGain(preamp: 0, bands: hot) <= -12)
}

@Test func clampsGlobalGain() {
    let flat = Array(repeating: 0.0, count: 10)
    #expect(EqMath.effectiveGlobalGain(preamp: 100, bands: flat) == 24)
    #expect(EqMath.effectiveGlobalGain(preamp: -100, bands: flat) == -24)
    #expect(EqMath.effectiveGlobalGain(preamp: .nan, bands: flat) == 0)
}

@Test func cutsDoNotAddGain() {
    let cut = Array(repeating: -6.0, count: 10)
    #expect(EqMath.effectiveGlobalGain(preamp: 0, bands: cut) == 0)
}

@Test func halfShareLeavesTheRestToTheLimiter() {
    let boost = [6.0, 5, 3, 1, 0, 0, 0, 0, 0, 0]
    let full = EqMath.effectiveGlobalGain(preamp: 0, bands: boost)
    let half = EqMath.effectiveGlobalGain(preamp: 0, bands: boost, share: 0.5)
    #expect(abs(half - full / 2) < 0.001)
}
