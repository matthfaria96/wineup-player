import Foundation

/// Medida de volume percebido de uma faixa (EBU R128 / ITU-R BS.1770).
public struct LoudnessInfo: Sendable, Codable, Equatable {
    /// Volume integrado, em LUFS.
    public var integrated: Double
    /// Pico de amostra (linear, 1 = 0 dBFS).
    public var peak: Double

    public init(integrated: Double, peak: Double) {
        self.integrated = integrated
        self.peak = peak
    }
}

/// Medidor BS.1770-4: filtro K (prateleira + passa-alta), blocos de 400 ms com 75% de sobreposição,
/// portão absoluto de -70 LUFS e relativo de -10 LU. Coeficientes calculados para qualquer taxa
/// (mesma fórmula do libebur128).
public struct LoudnessMeter: Sendable {
    private let channels: Int
    private var stages: [[Biquad]]
    private let blockSize: Int
    private let hop: Int
    private var energy: [Double]   // energia filtrada acumulada no trecho atual (por canal)
    private var ring: [[Double]]   // energia de cada passo de 100 ms
    private var stepCount = 0
    private var stepEnergy: [Double]
    private var blocks: [Double] = []
    private(set) public var peak: Double = 0

    public init(sampleRate: Double, channels: Int) {
        self.channels = max(1, channels)
        let pre = Biquad.preFilter(sampleRate: sampleRate), rlb = Biquad.rlbFilter(sampleRate: sampleRate)
        stages = Array(repeating: [pre, rlb], count: self.channels)
        hop = max(1, Int(sampleRate * 0.1))
        blockSize = hop * 4
        energy = Array(repeating: 0, count: self.channels)
        stepEnergy = Array(repeating: 0, count: self.channels)
        ring = []
    }

    /// Alimenta amostras não intercaladas (um array por canal, mesmo tamanho).
    public mutating func process(_ planar: [UnsafeBufferPointer<Float>]) {
        guard let frames = planar.first?.count else { return }
        for i in 0..<frames {
            for c in 0..<min(channels, planar.count) {
                let x = Double(planar[c][i])
                let a = abs(x)
                if a > peak { peak = a }
                let y = stages[c][1].run(stages[c][0].run(x))
                stepEnergy[c] += y * y
            }
            stepCount += 1
            if stepCount == hop { closeStep() }
        }
    }

    private mutating func closeStep() {
        ring.append(stepEnergy)
        if ring.count > 4 { ring.removeFirst() }
        if ring.count == 4 {
            // Canais L/R/C com peso 1 (surround 1,41 não se aplica a estéreo/mono).
            var sum = 0.0
            for c in 0..<channels { sum += ring.reduce(0) { $0 + $1[c] } / Double(blockSize) }
            blocks.append(sum)
        }
        stepEnergy = Array(repeating: 0, count: channels)
        stepCount = 0
    }

    /// Volume integrado (nil se o áudio é curto demais ou silêncio).
    public func integrated() -> Double? {
        func lufs(_ z: Double) -> Double { -0.691 + 10 * log10(z) }
        let absGated = blocks.filter { $0 > 0 && lufs($0) > -70 }
        guard !absGated.isEmpty else { return nil }
        let relThreshold = lufs(absGated.reduce(0, +) / Double(absGated.count)) - 10
        let gated = absGated.filter { lufs($0) > relThreshold }
        guard !gated.isEmpty else { return nil }
        return lufs(gated.reduce(0, +) / Double(gated.count))
    }
}

struct Biquad: Sendable {
    var b0, b1, b2, a1, a2: Double
    var z1 = 0.0, z2 = 0.0

    mutating func run(_ x: Double) -> Double {
        let y = b0 * x + z1
        z1 = b1 * x - a1 * y + z2
        z2 = b2 * x - a2 * y
        return y
    }

    static func preFilter(sampleRate rate: Double) -> Biquad {
        let f0 = 1681.974450955533, g = 3.999843853973347, q = 0.7071752369554196
        let k = tan(.pi * f0 / rate)
        let vh = pow(10, g / 20), vb = pow(vh, 0.4996667741545416)
        let a0 = 1 + k / q + k * k
        return Biquad(b0: (vh + vb * k / q + k * k) / a0, b1: 2 * (k * k - vh) / a0,
                      b2: (vh - vb * k / q + k * k) / a0, a1: 2 * (k * k - 1) / a0, a2: (1 - k / q + k * k) / a0)
    }

    static func rlbFilter(sampleRate rate: Double) -> Biquad {
        let f0 = 38.13547087602444, q = 0.5003270373238773
        let k = tan(.pi * f0 / rate)
        let a0 = 1 + k / q + k * k
        return Biquad(b0: 1, b1: -2, b2: 1, a1: 2 * (k * k - 1) / a0, a2: (1 - k / q + k * k) / a0)
    }
}

/// Ganho da Correção de Som: leva a faixa ao nível alvo, sem passar de ±12 dB
/// e sem estourar (o pico depois do ganho fica abaixo de 0 dBFS).
public enum SoundCorrection {
    public static let defaultTarget = -14.0
    public static let maxDB = 12.0

    public static func linearGain(target: Double, loudness: LoudnessInfo) -> Double {
        guard loudness.integrated.isFinite else { return 1 }
        let db = min(maxDB, max(-maxDB, target - loudness.integrated))
        var linear = pow(10, db / 20)
        if loudness.peak > 0, loudness.peak.isFinite { linear = min(linear, 0.98 / loudness.peak) }
        return linear
    }

    /// Sem medida ainda: estima pelo ReplayGain das tags (referência de -18 LUFS).
    public static func estimate(from tags: ReplayGainInfo) -> LoudnessInfo? {
        guard let gain = tags.trackGain ?? tags.albumGain, gain.isFinite else { return nil }
        return LoudnessInfo(integrated: -18 - gain, peak: tags.trackPeak ?? tags.albumPeak ?? 0)
    }
}
