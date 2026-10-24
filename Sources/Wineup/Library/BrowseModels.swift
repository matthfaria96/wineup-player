import Foundation
import WineupCore

/// Estilo da lista de faixas, parte do "design de exibição".
enum ListStyle: String, CaseIterable, Identifiable {
    case compact, detailed, grid

    var id: String { rawValue }

    var title: String {
        switch self {
        case .compact: String(localized: "Compacta")
        case .detailed: String(localized: "Com detalhes")
        case .grid: String(localized: "Grade")
        }
    }
}

extension MarkColor {
    var displayName: String {
        switch self {
        case .green: String(localized: "Verde")
        case .blue: String(localized: "Azul")
        case .purple: String(localized: "Roxa")
        case .red: String(localized: "Vermelha")
        case .orange: String(localized: "Laranja")
        case .yellow: String(localized: "Amarela")
        }
    }
}

/// Chaves de preferências de exibição (UserDefaults), também levadas no perfil do usuário.
enum DisplayKeys {
    static let layout = "layoutMode.v2"
    static let theme = "themeID"
    static let browseMode = "browseMode"
    static let viewMode = "viewMode"
    static let listStyle = "listStyle"
    static let showColorTags = "showColorTagPlaylists"
}
