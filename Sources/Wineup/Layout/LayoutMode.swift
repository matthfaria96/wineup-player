import Foundation

enum LayoutMode: String, CaseIterable, Identifiable {
    case standard, compact, full

    var id: String { rawValue }

    /// Layout do primeiro uso: o Completo, com todos os painéis.
    static let firstUse = LayoutMode.full

    var name: String {
        switch self {
        case .standard: "Padrão"
        case .compact: "Compacto"
        case .full: "Completo"
        }
    }

    var detail: String {
        switch self {
        case .standard: "Playlist à esquerda; player, equalizador e capa à direita"
        case .compact: "Player, equalizador e playlist numa coluna"
        case .full: "Todos os painéis, com letras"
        }
    }

    var minSize: (width: Double, height: Double) {
        switch self {
        // Altura certa para a capa quadrada na largura da coluna (~380), sem texto embaixo:
        // Player 236 + FX 190 + Capa (título 24 + moldura + 12 + ~341 + 12) + espaçamentos e barra.
        case .standard: (820, 888)
        case .compact: (430, 760)
        case .full: (1160, 888)
        }
    }

    static func named(_ raw: String) -> LayoutMode {
        LayoutMode(rawValue: raw) ?? .standard
    }
}
