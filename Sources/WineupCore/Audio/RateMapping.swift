import Foundation

/// Tempo restante em parede conforme a velocidade de reprodução.
/// Nota: `currentTime` do SFB já é tempo de conteúdo; progresso e letras NÃO são
/// corrigidos pela taxa (medido na pesquisa). Só o tempo restante em parede usa a taxa.
public enum RateMapping {
    public static func remainingWallSeconds(total: Double, current: Double, rate: Double) -> Double {
        let r = (rate.isFinite && rate > 0) ? rate : 1
        return max(0, total - current) / r
    }
}
