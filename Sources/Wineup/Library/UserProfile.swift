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
        // O que vem da tela é copiado aqui; banco, JSON e gravação ficam fora da thread principal.
        let info = trackInfo(state)
        let prefs = preferences()
        let db = state.library.database.map(CollectionsStore.init(database:))
        DispatchQueue.global(qos: .userInitiated).async {
            let ok = (try? JSONEncoder.pretty.encode(build(info: info, prefs: prefs, db: db)))
                .map { (try? $0.write(to: url, options: .atomic)) != nil } ?? false
            DispatchQueue.main.async {
                state.statusMessage = ok ? String(localized: "Perfil exportado.") : String(localized: "Não foi possível exportar o perfil.")
            }
        }
    }

    private static func trackInfo(_ state: PlayerState) -> [String: (String, String)] {
        Dictionary(state.tracks.compactMap { t in t.url.map { ($0.path, (t.title, t.artist)) } },
                   uniquingKeysWith: { a, _ in a })
    }

    private static func preferences() -> [String: String] {
        var prefs: [String: String] = [:]
        for key in prefKeys { if let v = UserDefaults.standard.object(forKey: key) { prefs[key] = "\(v)" } }
        return prefs
    }

    static func build(info: [String: (String, String)], prefs: [String: String], db: CollectionsStore?) -> UserProfile {
        func item(_ path: String) -> UserProfile.Item {
            let meta = info[path] ?? (URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent, "")
            return .init(path: path, title: meta.0, artist: meta.1)
        }
        let lists = ((try? db?.playlists()) ?? []).map { UserProfile.Playlist(name: $0.name, items: $0.paths.map(item)) }
        let marks = ((try? db?.marks()) ?? [:]).map { UserProfile.Mark(item: item($0.key), color: $0.value) }
        return UserProfile(playlists: lists, marks: marks, preferences: prefs)
    }

    static func importProfile(state: PlayerState) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.message = String(localized: "Escolha um perfil do Wineup (.wineupprofile)")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        // Lê e decodifica o arquivo fora da thread principal.
        DispatchQueue.global(qos: .userInitiated).async {
            guard let data = try? Data(contentsOf: url),
                  let profile = try? JSONDecoder.iso.decode(UserProfile.self, from: data) else { return }
            DispatchQueue.main.async { confirmImport(profile, state: state) }
        }
    }

    private static func confirmImport(_ profile: UserProfile, state: PlayerState) {
        let preview = NSAlert()
        preview.messageText = String(localized: "Importar perfil?")
        preview.informativeText = String(localized: "\(profile.playlists.count) playlists, \(profile.marks.count) tags de cor e \(profile.preferences.count) preferências. Nada do que você já tem será apagado; playlists com o mesmo nome ganham um número.")
        preview.addButton(withTitle: String(localized: "Importar"))
        preview.addButton(withTitle: String(localized: "Cancelar"))
        guard preview.runModal() == .alertFirstButtonReturn else { return }

        // Todos os caminhos (tags e playlists) resolvidos numa ida só ao banco, fora da thread principal.
        let items = profile.marks.map(\.item) + profile.playlists.flatMap(\.items)
        state.browser.resolvePaths(items.map { ($0.path, $0.title, $0.artist) }) { resolved in
            apply(profile, resolved: resolved, state: state)
        }
    }

    /// Aplica o perfil na thread principal; `resolved` segue a ordem: tags e depois as faixas de cada playlist.
    private static func apply(_ profile: UserProfile, resolved: [String?], state: PlayerState) {
        let browser = state.browser
        var missing = 0
        var next = resolved.makeIterator()
        for mark in profile.marks {
            let path = next.next() ?? nil
            guard let color = MarkColor(rawValue: mark.color), let path else { missing += 1; continue }
            browser.setMark(color, path: path)
        }
        for list in profile.playlists {
            let paths = list.items.compactMap { _ in next.next() ?? nil }
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
