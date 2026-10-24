import Foundation
import WineupAudio
import WineupCore

/// Lê o `LevelTap` a 30 Hz e publica níveis VU e bandas de espectro (0...1) com balística.
/// Snapshot ausente ou velho conta como silêncio.
@MainActor
final class MeterModel: ObservableObject {
    @Published private(set) var levels: [Double] = [0, 0]
    /// Nível por canal (0...1) do medidor de barras, numa escala que acompanha a dinâmica da música.
    @Published private(set) var bars: [Double] = [0, 0]
    @Published private(set) var bands: [Double] = Array(repeating: 0, count: MeterModel.bandCount)
    /// O espectro (FFT) só é calculado se alguma tela o exibe.
    var computesSpectrum = false

    static let bandCount = 20
    private static let publishThreshold = 0.005

    private let analyzer = SpectrumAnalyzer(size: 1024, bandCount: MeterModel.bandCount, minHz: 40, maxHz: 16_000)
    private var timer: Timer?
    private var lastTick = ProcessInfo.processInfo.systemUptime
    private var barMeters = [BarMeter(), BarMeter()]
    private var currentSnapshot: MeterSnapshot?
    /// Telas que mostram o medidor agora. O relógio só para quando a última sai: ao trocar de layout, a
    /// tela nova aparece antes de a antiga sumir, e parar no `onDisappear` da antiga deixava as barras mortas.
    private var viewers = 0

    func attach(tap: LevelTap) {
        viewers += 1
        if timer == nil { start(tap: tap) }
    }

    func detach() {
        viewers = max(0, viewers - 1)
        if viewers == 0 { stop() }
    }

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
        // O tap entrega blocos de até ~0,1 s (4 800 quadros a 48 kHz): só conta como silêncio depois de 0,25 s sem dados.
        let fresh = tap.snapshot().flatMap { MeterMath.isStale(timestamp: $0.timestamp, now: now, maxAge: 0.25) ? nil : $0 }
        currentSnapshot = fresh
        if let snap = fresh {
            targetLevels = (0..<2).map { channel in
                let rms = snap.rms.indices.contains(channel) ? snap.rms[channel] : (snap.rms.first ?? 0)
                return MeterMath.dbToMeter(20 * log10(max(rms, 1e-9)))
            }
            if computesSpectrum {
                targetBands = analyzer.bands(samples: snap.samples, sampleRate: snap.sampleRate)
            }
        }

        let nextLevels = zip(levels, targetLevels).map {
            Double(MeterMath.ballistic(current: Float($0), target: $1, dt: dt))
        }
        let nextBands = zip(bands, targetBands).map {
            Double(MeterMath.ballistic(current: Float($0), target: $1, dt: dt))
        }
        if Self.changed(levels, nextLevels) { levels = nextLevels }
        let rms: [Float] = (0..<2).map { channel in
            guard let snap = currentSnapshot else { return 0 }
            return snap.rms.indices.contains(channel) ? snap.rms[channel] : (snap.rms.first ?? 0)
        }
        let nextBars = (0..<2).map { Double(barMeters[$0].next(rms: rms[$0], dt: dt)) }
        if Self.changed(bars, nextBars) { bars = nextBars }
        if Self.changed(bands, nextBands) { bands = nextBands }
    }

    private static func changed(_ old: [Double], _ new: [Double]) -> Bool {
        guard old.count == new.count else { return true }
        return zip(old, new).contains { abs($0 - $1) > publishThreshold }
    }
}
