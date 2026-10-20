import Foundation

public enum EqMath {
    /// As 10 bandas do app (Hz).
    public static let bandFrequencies: [Double] = [60, 170, 310, 600, 1_000, 2_000, 5_000, 8_000, 12_000, 16_000]

    /// Desvio padrão (em oitavas) da resposta de cada banda paramétrica.
    static let sigmaOctaves = 0.7

    /// Maior ganho positivo (dB) da soma das respostas das bandas numa grade log de 200 pontos.
    public static func peakResponseDB(bands: [Double]) -> Double {
        let gains = bands.map { $0.isFinite ? $0 : 0 }
        let count = min(gains.count, bandFrequencies.count)
        guard count > 0 else { return 0 }
        let points = 200
        let lo = log2(20.0), hi = log2(20_000.0)
        var peak = 0.0
        for i in 0..<points {
            let f = lo + (hi - lo) * Double(i) / Double(points - 1)
            var sum = 0.0
            for b in 0..<count {
                let d = f - log2(bandFrequencies[b])
                sum += gains[b] * exp(-(d * d) / (2 * sigmaOctaves * sigmaOctaves))
            }
            peak = max(peak, sum)
        }
        return peak
    }

    /// Ganho global efetivo: preamp menos o pico positivo (compensação), limitado a +/-24 dB.
    public static func effectiveGlobalGain(preamp: Double, bands: [Double], autoCompensate: Bool = true) -> Double {
        let pre = preamp.isFinite ? preamp : 0
        let comp = autoCompensate ? max(0, peakResponseDB(bands: bands)) : 0
        return min(24, max(-24, pre - comp))
    }
}
