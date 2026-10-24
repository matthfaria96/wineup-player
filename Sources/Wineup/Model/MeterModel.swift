import Combine
import Foundation
import WineupAudio
import WineupCore

/// Lê o `LevelTap` a 30 Hz e publica níveis VU e de barras (0...1) com balística.
/// Snapshot ausente ou velho conta como silêncio. Em silêncio (pausado/parado) o relógio cai para
/// 4 Hz só para perceber a volta do som; com a janela principal invisível ele para de vez.
@MainActor
final class MeterModel: ObservableObject {
    @Published private(set) var levels: [Double] = [0, 0]
    /// Nível por canal (0...1) do medidor de barras, numa escala que acompanha a dinâmica da música.
    @Published private(set) var bars: [Double] = [0, 0]
    private static let publishThreshold = 0.005

    private var timer: Timer?
    private var lastTick = ProcessInfo.processInfo.systemUptime
    private var barMeters = [BarMeter(), BarMeter()]
    private var currentSnapshot: MeterSnapshot?
    /// Telas que mostram o medidor agora. O relógio só para quando a última sai: ao trocar de layout, a
    /// tela nova aparece antes de a antiga sumir, e parar no `onDisappear` da antiga deixava as barras mortas.
    private var viewers = 0
    private var tap: LevelTap?
    /// Em silêncio: relógio lento, nada a publicar.
    private var idle = false
    private var windowVisible = true
    private var visibilityWatch: AnyCancellable?

    private static let activeInterval = 1.0 / 30.0
    private static let idleInterval = 1.0 / 4.0

    func attach(tap: LevelTap) {
        viewers += 1
        self.tap = tap
        if visibilityWatch == nil {
            visibilityWatch = WindowVisibility.shared.$mainVisible.removeDuplicates().sink { [weak self] visible in
                MainActor.assumeIsolated { self?.windowVisibilityChanged(visible) }
            }
        }
        if timer == nil, windowVisible { start(tap: tap) }
    }

    func detach() {
        viewers = max(0, viewers - 1)
        if viewers == 0 { stop() }
    }

    func start(tap: LevelTap) {
        stop()
        self.tap = tap
        lastTick = ProcessInfo.processInfo.systemUptime
        schedule(interval: idle ? Self.idleInterval : Self.activeInterval)
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// O som voltou (play): sai do modo lento na hora, sem esperar o próximo tique lento.
    func wake() {
        guard idle else { return }
        idle = false
        if timer != nil { schedule(interval: Self.activeInterval) }
    }

    private func schedule(interval: TimeInterval) {
        timer?.invalidate()
        guard let tap else { timer = nil; return }
        let newTimer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick(tap: tap) }
        }
        RunLoop.main.add(newTimer, forMode: .common)
        timer = newTimer
    }

    private func windowVisibilityChanged(_ visible: Bool) {
        windowVisible = visible
        if !visible { stop() }
        else if viewers > 0, timer == nil, let tap { start(tap: tap) }
    }

    private func tick(tap: LevelTap) {
        let now = ProcessInfo.processInfo.systemUptime
        let dt = Float(max(0, now - lastTick))
        lastTick = now

        var targetLevels: [Float] = [0, 0]
        // O tap entrega blocos de até ~0,1 s (4 800 quadros a 48 kHz): só conta como silêncio depois de 0,25 s sem dados.
        let fresh = tap.snapshot().flatMap { MeterMath.isStale(timestamp: $0.timestamp, now: now, maxAge: 0.25) ? nil : $0 }
        currentSnapshot = fresh
        if idle {
            guard fresh != nil else { return }
            wake()
        }
        if let snap = fresh {
            targetLevels = (0..<2).map { channel in
                let rms = snap.rms.indices.contains(channel) ? snap.rms[channel] : (snap.rms.first ?? 0)
                return MeterMath.dbToMeter(20 * log10(max(rms, 1e-9)))
            }
        }

        let nextLevels = zip(levels, targetLevels).map {
            Double(MeterMath.ballistic(current: Float($0), target: $1, dt: dt))
        }
        if Self.changed(levels, nextLevels) { levels = nextLevels }
        let rms: [Float] = (0..<2).map { channel in
            guard let snap = currentSnapshot else { return 0 }
            return snap.rms.indices.contains(channel) ? snap.rms[channel] : (snap.rms.first ?? 0)
        }
        let nextBars = (0..<2).map { Double(barMeters[$0].next(rms: rms[$0], dt: dt)) }
        if Self.changed(bars, nextBars) { bars = nextBars }
        if fresh == nil, Self.isSilent(levels), Self.isSilent(bars) { enterIdle() }
    }

    /// Tudo já caiu a zero sem som chegando: zera de vez e passa ao relógio lento.
    private func enterIdle() {
        idle = true
        if levels.contains(where: { $0 != 0 }) { levels = [0, 0] }
        if bars.contains(where: { $0 != 0 }) { bars = [0, 0] }
        schedule(interval: Self.idleInterval)
    }

    private static func isSilent(_ values: [Double]) -> Bool { values.allSatisfy { $0 < 0.01 } }

    private static func changed(_ old: [Double], _ new: [Double]) -> Bool {
        guard old.count == new.count else { return true }
        return zip(old, new).contains { abs($0 - $1) > publishThreshold }
    }
}
