import AVFoundation

/// Cadeia de efeitos TimePitch -> EQ -> mixer de balanço (pan + ganho), independente do SFB.
public final class EffectChain: @unchecked Sendable {
    public static let bandFrequencies: [Float] = [60, 170, 310, 600, 1_000, 2_000, 5_000, 8_000, 12_000, 16_000]

    public let timePitch = AVAudioUnitTimePitch()
    public let eq = AVAudioUnitEQ(numberOfBands: 10)
    public let balance = AVAudioMixerNode()
    /// Mixer de downmix: no modo L/R entrega mono (esquerda+direita somadas) ao balanço.
    public let downmix = AVAudioMixerNode()

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
        for node in [timePitch, eq, downmix, balance] as [AVAudioNode] { engine.attach(node) }
    }

    public func connect(_ engine: AVAudioEngine, from source: AVAudioNode, to sink: AVAudioNode, format: AVAudioFormat) {
        engine.connect(source, to: timePitch, format: format)
        reconnectInternal(engine, to: sink, format: format)
    }

    /// Religa os três elos internos; nunca só parte da cadeia.
    /// Lado único (L ou R): a música inteira (os dois canais somados) vai para um lado só.
    public private(set) var singleSide = false

    public func reconnectInternal(_ engine: AVAudioEngine, to sink: AVAudioNode, format: AVAudioFormat) {
        engine.connect(timePitch, to: eq, format: format)
        engine.connect(eq, to: downmix, format: format)
        if singleSide, let mono = AVAudioFormat(standardFormatWithSampleRate: format.sampleRate, channels: 1) {
            // Saída mono do downmix: soma esquerda+direita; o pan do balanço leva tudo para um lado.
            engine.connect(downmix, to: balance, format: mono)
        } else {
            engine.connect(downmix, to: balance, format: format)
        }
        engine.connect(balance, to: sink, format: format)
    }

    public func setRate(_ rate: Float) {
        timePitch.rate = Self.clamp(rate, 0.5, 3.0, fallback: 1)
        // Em 1× o TimePitch não altera nada, mas custa CPU: fica em bypass.
        timePitch.bypass = abs(timePitch.rate - 1) < 0.001
    }

    /// -1 = tudo à esquerda, 0 = normal (estéreo original), 1 = tudo à direita.
    public func setSide(_ side: Int, engine: AVAudioEngine, sink: AVAudioNode, format: AVAudioFormat) {
        singleSide = side != 0
        reconnectInternal(engine, to: sink, format: format)
        balance.pan = Float(max(-1, min(1, side)))
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
