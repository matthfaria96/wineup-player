import Foundation

enum LayoutMode: String, CaseIterable, Identifiable {
    case standard, compact, full

    var id: String { rawValue }

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
        // Altura mínima garante a capa quadrada na largura total da coluna (380):
        // Player 236 + FX 190 + Capa (24 + 12 + 356 + 12 + ~70) + espaçamentos e barra.
        case .standard: (820, 960)
        case .compact: (430, 760)
        case .full: (1160, 960)
        }
    }

    static func named(_ raw: String) -> LayoutMode {
        LayoutMode(rawValue: raw) ?? .standard
    }
}
