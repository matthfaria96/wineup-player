import Foundation
import Testing
@testable import WineupCore

@Test func albumFallsBackToTrack() {
    let g = ReplayGainMath.linearGain(mode: .album, info: ReplayGainInfo(trackGain: -6), preventClipping: true)
    #expect(abs(g - pow(10, -6.0 / 20)) < 1e-9)
}

@Test func noTagOrOffIsUnity() {
    #expect(ReplayGainMath.linearGain(mode: .track, info: ReplayGainInfo(), preventClipping: true) == 1)
    #expect(ReplayGainMath.linearGain(mode: .off, info: ReplayGainInfo(trackGain: -6), preventClipping: true) == 1)
}

@Test func peakLimitsGain() {
    let g = ReplayGainMath.linearGain(mode: .track, info: ReplayGainInfo(trackGain: 10, trackPeak: 0.9), preventClipping: true)
    #expect(abs(g - 1 / 0.9) < 1e-9)
    let free = ReplayGainMath.linearGain(mode: .track, info: ReplayGainInfo(trackGain: 10, trackPeak: 0.9), preventClipping: false)
    #expect(abs(free - pow(10, 0.5)) < 1e-9)
}

@Test func hostileValues() {
    #expect(ReplayGainMath.linearGain(mode: .track, info: ReplayGainInfo(trackGain: .nan), preventClipping: true) == 1)
    #expect(ReplayGainMath.linearGain(mode: .track, info: ReplayGainInfo(trackGain: .infinity), preventClipping: true) == 1)
    let big = ReplayGainMath.linearGain(mode: .track, info: ReplayGainInfo(trackGain: 99), preventClipping: false)
    #expect(abs(big - pow(10, 30.0 / 20)) < 1e-9)
    let badPeak = ReplayGainMath.linearGain(mode: .track, info: ReplayGainInfo(trackGain: 6, trackPeak: 0), preventClipping: true)
    #expect(abs(badPeak - pow(10, 6.0 / 20)) < 1e-9)
    let nanPeak = ReplayGainMath.linearGain(mode: .track, info: ReplayGainInfo(trackGain: 6, trackPeak: .nan), preventClipping: true)
    #expect(abs(nanPeak - pow(10, 6.0 / 20)) < 1e-9)
}
