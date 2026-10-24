import AppKit
import Foundation
import UniformTypeIdentifiers
import WineupCore
import WineupLibrary

/// Arquivo de perfil do usuário: playlists, tags de cor, preferências e EQ.
struct UserProfile: Codable {
    struct Item: Codable { let path: String; let title: String; let artist: String }
    struct Playlist: Codable { let name: String; let items: [Item] }
    struct Mark: Codable { let item: Item; let color: String }

    var version = 1
    var exportedAt = Date()
    var playlists: [Playlist]
    var marks: [Mark]
    var preferences: [String: String]
}

enum ProfileManager {
    static let prefKeys = [DisplayKeys.layout, DisplayKeys.theme, DisplayKeys.viewMode,
                           DisplayKeys.listStyle, DisplayKeys.showColorTags]

    static func export(state: PlayerState) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = String(localized: "Meu perfil.wineupprofile")
        panel.message = String(localized: "Exportar perfil do Wineup (playlists, tags e preferências)")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let data = try JSONEncoder.pretty.encode(build(state: state))
            try data.write(to: url, options: .atomic)
            state.statusMessage = String(localized: "Perfil exportado.")
        } catch {
            state.statusMessage = String(localized: "Não foi possível exportar o perfil.")
        }
    }

    static func build(state: PlayerState) -> UserProfile {
        let db = state.library.database.map(CollectionsStore.init(database:))
        let info: [String: (String, String)] = Dictionary(
            state.tracks.compactMap { t in t.url.map { ($0.path, (t.title, t.artist)) } },
            uniquingKeysWith: { a, _ in a })
        func item(_ path: String) -> UserProfile.Item {
            let meta = info[path] ?? (URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent, "")
            return .init(path: path, title: meta.0, artist: meta.1)
        }
        let lists = ((try? db?.playlists()) ?? []).map { UserProfile.Playlist(name: $0.name, items: $0.paths.map(item)) }
        let marks = ((try? db?.marks()) ?? [:]).map { UserProfile.Mark(item: item($0.key), color: $0.value) }
        var prefs: [String: String] = [:]
        for key in prefKeys { if let v = UserDefaults.standard.object(forKey: key) { prefs[key] = "\(v)" } }
        return UserProfile(playlists: lists, marks: marks, preferences: prefs)
    }

    static func importProfile(state: PlayerState) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.message = String(localized: "Escolha um perfil do Wineup (.wineupprofile)")
        guard panel.runModal() == .OK, let url = panel.url,
              let data = try? Data(contentsOf: url),
              let profile = try? JSONDecoder.iso.decode(UserProfile.self, from: data) else {
            return
        }
        let preview = NSAlert()
        preview.messageText = String(localized: "Importar perfil?")
        preview.informativeText = String(localized: "\(profile.playlists.count) playlists, \(profile.marks.count) tags de cor e \(profile.preferences.count) preferências. Nada do que você já tem será apagado; playlists com o mesmo nome ganham um número.")
        preview.addButton(withTitle: String(localized: "Importar"))
        preview.addButton(withTitle: String(localized: "Cancelar"))
        guard preview.runModal() == .alertFirstButtonReturn else { return }

        let browser = state.browser
        var missing = 0
        for mark in profile.marks {
            guard let color = MarkColor(rawValue: mark.color),
                  let path = browser.resolvePath(path: mark.item.path, title: mark.item.title, artist: mark.item.artist)
            else { missing += 1; continue }
            browser.setMark(color, path: path)
        }
        for list in profile.playlists {
            let paths = list.items.compactMap { browser.resolvePath(path: $0.path, title: $0.title, artist: $0.artist) }
            missing += list.items.count - paths.count
            browser.createPlaylist(named: list.name, paths: paths)
        }
        for (key, value) in profile.preferences where prefKeys.contains(key) {
            if key == DisplayKeys.showColorTags { UserDefaults.standard.set(value == "1" || value == "true", forKey: key) }
            else { UserDefaults.standard.set(value, forKey: key) }
        }
        browser.refresh()
        state.statusMessage = missing == 0 ? String(localized: "Perfil importado.") : String(localized: "Perfil importado; \(missing) faixas não encontradas nesta biblioteca.")
    }
}

private extension JSONEncoder {
    static var pretty: JSONEncoder {
        let e = JSONEncoder(); e.outputFormatting = [.prettyPrinted, .sortedKeys]; e.dateEncodingStrategy = .iso8601; return e
    }
}

private extension JSONDecoder {
    static var iso: JSONDecoder { let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d }
}
