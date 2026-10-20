import Foundation
import WineupAudio
import WineupCore

/// Lê o `LevelTap` a 30 Hz e publica níveis VU e bandas de espectro (0...1) com balística.
/// Snapshot ausente ou velho conta como silêncio.
@MainActor
final class MeterModel: ObservableObject {
    @Published private(set) var levels: [Double] = [0, 0]
    @Published private(set) var bands: [Double] = Array(repeating: 0, count: MeterModel.bandCount)

    static let bandCount = 20
    private static let publishThreshold = 0.005

    private let analyzer = SpectrumAnalyzer(size: 1024, bandCount: MeterModel.bandCount, minHz: 40, maxHz: 16_000)
    private var timer: Timer?
    private var lastTick = ProcessInfo.processInfo.systemUptime

    func start(tap: LevelTap) {
        stop()
        lastTick = ProcessInfo.processInfo.systemUptime
        let newTimer = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick(tap: tap) }
        }
        RunLoop.main.add(newTimer, forMode: .common)
        timer = newTimer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func tick(tap: LevelTap) {
        let now = ProcessInfo.processInfo.systemUptime
        let dt = Float(max(0, now - lastTick))
        lastTick = now

        var targetLevels: [Float] = [0, 0]
        var targetBands = [Float](repeating: 0, count: Self.bandCount)
        if let snap = tap.snapshot(), !MeterMath.isStale(timestamp: snap.timestamp, now: now) {
            targetLevels = (0..<2).map { channel in
                let rms = snap.rms.indices.contains(channel) ? snap.rms[channel] : (snap.rms.first ?? 0)
                return MeterMath.dbToMeter(20 * log10(max(rms, 1e-9)))
            }
            targetBands = analyzer.bands(samples: snap.samples, sampleRate: snap.sampleRate)
        }

        let nextLevels = zip(levels, targetLevels).map {
            Double(MeterMath.ballistic(current: Float($0), target: $1, dt: dt))
        }
        let nextBands = zip(bands, targetBands).map {
            Double(MeterMath.ballistic(current: Float($0), target: $1, dt: dt))
        }
        if Self.changed(levels, nextLevels) { levels = nextLevels }
        if Self.changed(bands, nextBands) { bands = nextBands }
    }

    private static func changed(_ old: [Double], _ new: [Double]) -> Bool {
        guard old.count == new.count else { return true }
        return zip(old, new).contains { abs($0 - $1) > publishThreshold }
    }
}
