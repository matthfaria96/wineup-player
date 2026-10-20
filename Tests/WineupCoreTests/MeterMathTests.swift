import Foundation
import Testing
@testable import WineupCore

private func sine(_ hz: Double, rate: Double = 44_100, count: Int = 1024) -> [Float] {
    (0..<count).map { Float(sin(2 * .pi * hz * Double($0) / rate)) }
}

@Test func sineLightsItsBand() {
    let a = SpectrumAnalyzer()
    let bands = a.bands(samples: sine(1000), sampleRate: 44_100)
    #expect(bands.count == 20)
    let top = bands.indices.max { bands[$0] < bands[$1] }!
    let lo = 40 * exp(log(16_000.0 / 40) * Double(top) / 20)
    let hi = 40 * exp(log(16_000.0 / 40) * Double(top + 1) / 20)
    #expect(lo <= 1000 * 1.1 && hi >= 1000 * 0.9)
    for i in bands.indices where abs(i - top) > 2 {
        #expect(bands[i] <= bands[top] - 20.0 / 60)
    }
}

@Test func silenceIsZero() {
    let bands = SpectrumAnalyzer().bands(samples: [Float](repeating: 0, count: 1024), sampleRate: 44_100)
    #expect(bands.allSatisfy { $0 == 0 })
}

@Test func oddSizesAreSafe() {
    let a = SpectrumAnalyzer()
    #expect(a.bands(samples: [], sampleRate: 44_100).count == 20)
    #expect(a.bands(samples: sine(500, count: 5000), sampleRate: 48_000).count == 20)
    #expect(a.bands(samples: [.nan, .infinity], sampleRate: 44_100).count == 20)
}

@Test func staleness() {
    #expect(MeterMath.isStale(timestamp: 10, now: 10.15))
    #expect(!MeterMath.isStale(timestamp: 10, now: 10.05))
}

@Test func ballisticDecaysAndRisesInstantly() {
    let d = MeterMath.ballistic(current: 1, target: 0, dt: 0.1)
    #expect(d < 1 && d > 0)
    #expect(MeterMath.ballistic(current: 0.2, target: 0.9, dt: 0.01) == 0.9)
}

@Test func dbToMeterMonotonic() {
    #expect(MeterMath.dbToMeter(-60) == 0)
    #expect(MeterMath.dbToMeter(0) == 1)
    #expect(MeterMath.dbToMeter(-30) < MeterMath.dbToMeter(-10))
}
