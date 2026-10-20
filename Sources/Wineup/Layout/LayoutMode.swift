import Foundation

enum LayoutMode: String, CaseIterable, Identifiable {
    case grid, compact, studio

    var id: String { rawValue }

    var name: String {
        switch self {
        case .grid: "Grade"
        case .compact: "Compacto"
        case .studio: "Estúdio"
        }
    }

    var detail: String {
        switch self {
        case .grid: "Todos os painéis lado a lado"
        case .compact: "Playlist grande + player à direita"
        case .studio: "Coluna do player, capa, letras e busca"
        }
    }

    var defaultSize: (width: Double, height: Double) {
        switch self {
        case .grid: (1180, 720)
        case .compact: (700, 700)
        case .studio: (1040, 700)
        }
    }

    static func named(_ raw: String) -> LayoutMode {
        LayoutMode(rawValue: raw) ?? .grid
    }
}

extension LayoutMode {
    var minSize: (width: Double, height: Double) {
        switch self {
        case .grid: (1060, 640)
        case .compact: (700, 660)
        case .studio: (1000, 660)
        }
    }
}
