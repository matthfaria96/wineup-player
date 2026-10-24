import Foundation

public enum MeterMath {
    public static let floorDB: Float = -60

    public static func dbToMeter(_ db: Float) -> Float {
        guard db.isFinite else { return db > 0 ? 1 : 0 }
        return min(1, max(0, (db - floorDB) / -floorDB))
    }

    public static func isStale(timestamp: TimeInterval, now: TimeInterval, maxAge: TimeInterval = 0.1) -> Bool {
        now - timestamp > maxAge
    }

    /// Sobe imediato, desce linear (`decayPerSecond` unidades normalizadas por segundo).
    public static func ballistic(current: Float, target: Float, dt: Float, decayPerSecond: Float = 1.5) -> Float {
        if target >= current { return target }
        return max(target, current - decayPerSecond * max(0, dt))
    }
}

/// Medidor de barras que acompanha a dinâmica da música: mistura o volume absoluto (−40…−6 dBFS) com a
/// distância do volume atual à média dos últimos ~2,5 s. Assim a barra passeia pelas três cores em qualquer
/// música: trechos abaixo da média no verde, na média no amarelo e só os picos acima dela no vermelho.
/// Calibrado em faixas reais: música alta fica ~30% verde, ~50% amarelo e ~18% vermelho.
public struct BarMeter: Sendable {
    public static let absoluteWeight: Float = 0.3
    public static let spanDB: Float = 12
    public static let center: Float = 0.5
    public static let averageSeconds: Float = 2.5
    public static let decayPerSecond: Float = 1.6
    public static let silenceDB: Float = -55

    public private(set) var value: Float = 0
    private var averageDB: Float = -20

    public init() {}

    /// Avança um quadro com o RMS (amplitude 0...1) e devolve o nível da barra (0...1).
    public mutating func next(rms: Float, dt: Float) -> Float {
        let db = 20 * log10(max(abs(rms), 1e-9))
        if db > Self.silenceDB { averageDB += (db - averageDB) * min(1, dt / Self.averageSeconds) }
        let absolute = min(1, max(0, (db + 40) / 34))
        let relative = db <= Self.silenceDB ? 0 : min(1, max(0, Self.center + (db - averageDB) / Self.spanDB))
        let target = Self.absoluteWeight * absolute + (1 - Self.absoluteWeight) * relative
        value = MeterMath.ballistic(current: value, target: target, dt: dt, decayPerSecond: Self.decayPerSecond)
        return value
    }
}

/// Forma de onda da barra de busca, com a mesma lógica do medidor de barras: o volume de cada trecho
/// pesa pelo valor absoluto (−40…−6 dBFS) e pela distância à média da própria música. Assim os trechos
/// fortes (refrão, graves) ficam altos e os calmos baixos, em qualquer música, alta ou baixa.
public enum Waveform {
    /// Agrupa janelas (média dos quadrados) em `count` trechos, em dBFS de RMS.
    public static func buckets(meanSquares: [Float], count: Int) -> [Float] {
        guard !meanSquares.isEmpty, count > 0 else { return [] }
        return (0..<count).map { b in
            let lo = b * meanSquares.count / count
            let hi = max(lo + 1, (b + 1) * meanSquares.count / count)
            let slice = meanSquares[min(lo, meanSquares.count - 1)..<min(hi, meanSquares.count)]
            let mean = slice.reduce(0, +) / Float(max(slice.count, 1))
            return 10 * log10(max(mean, 1e-12))
        }
    }

    /// Altura (0...1) de cada trecho. Silêncio vai a zero. `spanDB` menor = mais contraste entre trechos.
    public static func heights(_ levelsDB: [Float], spanDB: Float = BarMeter.spanDB) -> [Float] {
        let audible = levelsDB.filter { $0 > BarMeter.silenceDB }
        guard !audible.isEmpty else { return levelsDB.map { _ in 0 } }
        let average = audible.reduce(0, +) / Float(audible.count)
        return levelsDB.map { db in
            guard db > BarMeter.silenceDB else { return 0 }
            let absolute = min(1, max(0, (db + 40) / 34))
            let relative = min(1, max(0, BarMeter.center + (db - average) / spanDB))
            return BarMeter.absoluteWeight * absolute + (1 - BarMeter.absoluteWeight) * relative
        }
    }
}
