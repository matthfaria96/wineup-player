import Foundation
import WineupCore

/// Como o usuário quer ver a biblioteca.
enum BrowseMode: String, CaseIterable, Identifiable {
    case albums, artists, folders, genres, playlists

    var id: String { rawValue }

    var title: String {
        switch self {
        case .albums: String(localized: "Álbuns")
        case .artists: String(localized: "Bandas")
        case .folders: String(localized: "Pastas")
        case .genres: String(localized: "Estilos")
        case .playlists: String(localized: "Playlists")
        }
    }

    var symbol: String {
        switch self {
        case .albums: "square.stack"
        case .artists: "music.mic"
        case .folders: "folder"
        case .genres: "guitars"
        case .playlists: "music.note.list"
        }
    }
}

/// Um item da coluna de navegação (um álbum, uma banda, uma pasta, um estilo ou uma playlist).
struct BrowseGroup: Identifiable, Hashable {
    enum Kind: Hashable {
        case album(Int64)
        case singles
        case artist(Int64)
        case folder(String)
        case genre(String)
        case playlist(Int64)
        case colorTag(MarkColor)
        case allTracks
    }

    let kind: Kind
    let title: String
    let subtitle: String
    let count: Int

    var id: Kind { kind }

    var isUserPlaylist: Bool {
        if case .playlist = kind { return true }
        return false
    }
}

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
