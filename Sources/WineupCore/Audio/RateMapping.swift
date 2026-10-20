import Foundation

/// Mapeamento do slider de velocidade (0...1) para a taxa (0,5x...2,0x), logarítmico.
/// Nota: `currentTime` do SFB já é tempo de conteúdo; progresso e letras NÃO são
/// corrigidos pela taxa (medido na pesquisa). Só o tempo restante em parede usa a taxa.
public enum RateMapping {
    public static func rate(slider: Double) -> Double {
        let s = slider.isFinite ? min(1, max(0, slider)) : 0.5
        return 0.5 * pow(4, s)
    }

    public static func slider(rate: Double) -> Double {
        guard rate.isFinite, rate > 0 else { return 0.5 }
        let s = log(rate / 0.5) / log(4)
        return min(1, max(0, s))
    }

    public static func remainingWallSeconds(total: Double, current: Double, rate: Double) -> Double {
        let r = (rate.isFinite && rate > 0) ? rate : 1
        return max(0, total - current) / r
    }

    /// Balanço 0...1 para pan -1...1.
    public static func pan(balance: Double) -> Double {
        let b = balance.isFinite ? balance : 0.5
        return min(1, max(-1, b * 2 - 1))
    }
}
