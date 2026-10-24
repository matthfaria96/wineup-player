import Foundation

/// Uma travada da thread principal: em que passo aconteceu e quanto durou (ms).
public struct HangEvent: Equatable, Sendable {
    public let step: String
    public let milliseconds: Double

    public init(step: String, milliseconds: Double) {
        self.step = step
        self.milliseconds = milliseconds
    }
}

/// Resumo das travadas de um passo: quantas, a pior e o tempo total travado.
public struct HangStats: Equatable, Sendable {
    public let count: Int
    public let worst: Double
    public let total: Double

    public init(_ durations: [Double]) {
        count = durations.count
        worst = durations.max() ?? 0
        total = durations.reduce(0, +)
    }

    /// Estatística de cada passo de `steps` (passo sem travada fica com zeros).
    public static func byStep(_ events: [HangEvent], steps: [String]) -> [String: HangStats] {
        let grouped = Dictionary(grouping: events, by: \.step)
        return Dictionary(steps.map { step in (step, HangStats(grouped[step]?.map(\.milliseconds) ?? [])) },
                          uniquingKeysWith: { first, _ in first })
    }
}

/// Linha do resumo do teste de carga: passo, duração, pior travada, quantas e total (ms, tabulado).
public enum StressReport {
    public static let header = "passo\tduração ms\tpior travada ms\ttravadas\ttotal travado ms"

    public static func line(step: String, duration: Double, stats: HangStats) -> String {
        String(format: "%@\t%.0f\t%.0f\t%d\t%.0f", step, duration, stats.worst, stats.count, stats.total)
    }
}
