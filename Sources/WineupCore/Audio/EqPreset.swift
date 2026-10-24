import Foundation

public struct EqPreset: Codable, Sendable, Equatable, Identifiable {
    public var id: String { name }
    public let name: String
    public let preamp: Double
    public let bands: [Double]

    public static let bandCount = 10
    public static let maxNameLength = 64

    /// Valida (dados vêm do banco ou do usuário): nome trimado 1...64, 10 bandas finitas em +/-12, preamp em +/-24.
    public static func validated(name: String, preamp: Double, bands: [Double]) -> EqPreset? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= maxNameLength else { return nil }
        guard preamp.isFinite, abs(preamp) <= 24 else { return nil }
        guard bands.count == bandCount, bands.allSatisfy({ $0.isFinite && abs($0) <= 12 }) else { return nil }
        return EqPreset(name: trimmed, preamp: preamp, bands: bands)
    }

    /// Curvas suaves (no máximo +6 dB): mudam o timbre ao gosto, sem estourar nem "afundar" o resto da música.
    /// Bandas: 60, 170, 310, 600, 1K, 2K, 5K, 8K, 12K e 16K Hz.
    public static let builtIns: [EqPreset] = [
        EqPreset(name: "Flat", preamp: 0, bands: Array(repeating: 0, count: 10)),
        EqPreset(name: "Rock", preamp: 0, bands: [4, 3, 1, -1, -1, 1, 3, 4, 4, 3]),
        EqPreset(name: "Pop", preamp: 0, bands: [-1, 1, 3, 4, 3, 1, 0, 1, 2, 2]),
        EqPreset(name: "Jazz", preamp: 0, bands: [3, 2, 1, 1, -1, -1, 0, 1, 2, 3]),
        EqPreset(name: "Clássica", preamp: 0, bands: [2, 1, 0, 0, 0, 0, 0, 1, 2, 2]),
        EqPreset(name: "Eletrônica", preamp: 0, bands: [5, 4, 1, 0, -2, 0, 1, 2, 4, 4]),
        EqPreset(name: "Acústico", preamp: 0, bands: [2, 2, 1, 1, 2, 2, 3, 3, 2, 1]),
        EqPreset(name: "Volume baixo", preamp: 0, bands: [5, 3, 1, 0, -1, 0, 1, 3, 4, 4]),
        EqPreset(name: "Vintage", preamp: 0, bands: [2, 2, 1, 0, 0, -1, -2, -3, -4, -5]),
        EqPreset(name: "Bass Boost", preamp: 0, bands: [6, 5, 3, 1, 0, 0, 0, 0, 0, 0]),
        EqPreset(name: "Vocal", preamp: 0, bands: [-2, -1, 0, 2, 4, 4, 3, 1, 0, -1]),
    ]

    /// Nome mostrado na tela: os prontos (e "Custom") no idioma do app; os do usuário como ele escreveu.
    public static func displayName(_ name: String) -> String {
        switch name {
        case "Flat": String(localized: "Flat")
        case "Rock": String(localized: "Rock")
        case "Pop": String(localized: "Pop")
        case "Jazz": String(localized: "Jazz")
        case "Clássica": String(localized: "Clássica")
        case "Eletrônica": String(localized: "Eletrônica")
        case "Acústico": String(localized: "Acústico")
        case "Volume baixo": String(localized: "Volume baixo")
        case "Vintage": String(localized: "Vintage")
        case "Bass Boost": String(localized: "Bass Boost")
        case "Vocal": String(localized: "Vocal")
        case "Custom": String(localized: "Personalizado")
        default: name
        }
    }

    /// O que cada preset faz, para o menu.
    public static let builtInDetails: [String: String] = [
        "Flat": String(localized: "Sem ajuste: o som original da música."),
        "Rock": String(localized: "Graves e agudos mais fortes, médios recuados."),
        "Pop": String(localized: "Vozes e médios na frente, brilho leve."),
        "Jazz": String(localized: "Graves macios e agudos abertos, médios suaves."),
        "Clássica": String(localized: "Quase neutro, com um pouco mais de ar e corpo."),
        "Eletrônica": String(localized: "Grave forte e agudos brilhantes, médio contido."),
        "Acústico": String(localized: "Realça violões e vozes, natural."),
        "Volume baixo": String(localized: "Compensa graves e agudos que somem com o volume baixo."),
        "Vintage": String(localized: "Quente e abafado, como vinil ou rádio antigo."),
        "Bass Boost": String(localized: "Só reforça os graves."),
        "Vocal": String(localized: "Destaca a voz e tira o embolado dos graves."),
    ]

    public static func isBuiltInName(_ name: String) -> Bool {
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return builtIns.contains { $0.name.lowercased() == n }
    }
}
