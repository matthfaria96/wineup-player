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

/// Medidor de barras (24 barras: verde até 15, amarelo até 21, vermelho nas 3 últimas). Música alta e
/// constante não fica presa no vermelho: na média fica no amarelo; acima da média sobe ao vermelho;
/// abaixo, desce ao verde. Silêncio zera.
@Test func barMeterFollowsTheMusicDynamics() {
    let yellowStart: Float = 15.0 / 24.0, redStart: Float = 21.0 / 24.0, dt: Float = 1.0 / 30
    func amp(_ db: Float) -> Float { pow(10, db / 20) }
    var m = BarMeter()
    for _ in 0..<300 { _ = m.next(rms: amp(-9), dt: dt) }              // 10 s de música alta e constante
    #expect((yellowStart..<redStart).contains(m.value))
    #expect(m.next(rms: amp(-3), dt: dt) > redStart)                   // batida bem acima da média
    for _ in 0..<30 { _ = m.next(rms: amp(-20), dt: dt) }             // trecho calmo
    #expect(m.value < yellowStart)
    for _ in 0..<60 { _ = m.next(rms: 0, dt: dt) }
    #expect(m.value == 0)
}

/// Forma de onda: trecho forte mais alto que o calmo, silêncio zerado, e a mesma ordem vale para música baixa.
@Test func waveformFollowsLoudness() {
    let loud = Waveform.heights([-30, -18, -9, -60])
    #expect(loud[2] > loud[1] && loud[1] > loud[0] && loud[3] == 0)
    let quiet = Waveform.heights([-40, -32, -26])
    #expect(quiet[2] > quiet[1] && quiet[1] > quiet[0])
    let b = Waveform.buckets(meanSquares: [1, 1, 0.01, 0.01], count: 2)
    #expect(abs(b[0]) < 0.01 && abs(b[1] + 20) < 0.01)
}
