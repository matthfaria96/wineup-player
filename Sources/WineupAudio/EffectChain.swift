import AVFoundation

/// Cadeia de efeitos TimePitch -> EQ -> mixer de balanço (pan + ganho), independente do SFB.
public final class EffectChain: @unchecked Sendable {
    public static let bandFrequencies: [Float] = [60, 170, 310, 600, 1_000, 2_000, 5_000, 8_000, 12_000, 16_000]

    public let timePitch = AVAudioUnitTimePitch()
    public let eq = AVAudioUnitEQ(numberOfBands: 10)
    public let balance = AVAudioMixerNode()

    public var first: AVAudioNode { timePitch }

    public init() {
        for (index, band) in eq.bands.enumerated() where index < Self.bandFrequencies.count {
            band.filterType = .parametric
            band.frequency = Self.bandFrequencies[index]
            band.bandwidth = 1
            band.gain = 0
            band.bypass = false
        }
    }

    public func attach(to engine: AVAudioEngine) {
        for node in [timePitch, eq, balance] as [AVAudioNode] { engine.attach(node) }
    }

    public func connect(_ engine: AVAudioEngine, from source: AVAudioNode, to sink: AVAudioNode, format: AVAudioFormat) {
        engine.connect(source, to: timePitch, format: format)
        reconnectInternal(engine, to: sink, format: format)
    }

    /// Religa os três elos internos; nunca só parte da cadeia.
    public func reconnectInternal(_ engine: AVAudioEngine, to sink: AVAudioNode, format: AVAudioFormat) {
        engine.connect(timePitch, to: eq, format: format)
        engine.connect(eq, to: balance, format: format)
        engine.connect(balance, to: sink, format: format)
    }

    public func setRate(_ rate: Float) {
        timePitch.rate = Self.clamp(rate, 0.5, 2.0, fallback: 1)
    }

    public func setPan(_ pan: Float) {
        balance.pan = Self.clamp(pan, -1, 1, fallback: 0)
    }

    public func setGain(linear: Float) {
        balance.outputVolume = Self.clamp(linear, 0, 8, fallback: 1)
    }

    public func applyEqualizer(globalGain: Float, bands: [Float], bypass: Bool) {
        eq.globalGain = Self.clamp(globalGain, -24, 24, fallback: 0)
        for (index, band) in eq.bands.enumerated() {
            let value = index < bands.count ? bands[index] : 0
            band.gain = Self.clamp(value, -12, 12, fallback: 0)
            band.bypass = bypass
        }
    }

    private static func clamp(_ v: Float, _ lo: Float, _ hi: Float, fallback: Float) -> Float {
        v.isFinite ? min(max(v, lo), hi) : fallback
    }
}
