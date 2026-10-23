import AppKit
import Foundation
import WineupCore
import WineupLibrary

/// Como ver o conteúdo da pasta atual (independe de qual pasta é).
enum ViewMode: String, CaseIterable, Identifiable {
    case files, songs, albums, artists, genres, playlists, queue

    var id: String { rawValue }

    var title: String {
        switch self {
        case .files: "Pastas"
        case .songs: "Músicas"
        case .albums: "Álbuns"
        case .artists: "Artistas"
        case .genres: "Gêneros"
        case .playlists: "Playlists"
        case .queue: "Fila"
        }
    }

    var symbol: String {
        switch self {
        case .files: "folder"
        case .songs: "music.note.list"
        case .albums: "square.stack"
        case .artists: "music.mic"
        case .genres: "guitars"
        case .playlists: "list.star"
        case .queue: "list.number"
        }
    }

    /// Visões que mostram grupos (álbuns, artistas...) antes das faixas.
    var isGrouping: Bool { [.albums, .artists, .genres, .playlists].contains(self) }
}

/// Um item agrupado da visão (um álbum, artista, gênero, playlist ou tag de cor).
struct ViewGroup: Identifiable, Hashable {
    let id: String
    let title: String
    let subtitle: String
    let count: Int
    var tracks: [Track] = []
    var playlistID: Int64? = nil
    var color: MarkColor? = nil
    var coverURL: URL? = nil
}

/// Um passo do histórico: pasta + visão + grupo aberto.
struct NavEntry: Equatable {
    let folder: URL
    let view: ViewMode
    let groupID: String?
}

/// Locais padrão e favoritos.
enum NavPlaces {
    static let favoritesKey = "favoriteLocations"
    static let defaultFolderKey = "defaultFolder"

    static var music: URL { FileManager.default.urls(for: .musicDirectory, in: .userDomainMask)[0] }
    static var downloads: URL { FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0] }

    static var defaultFolder: URL? {
        // Testes/medições: WINEUP_DEFAULT_FOLDER substitui a preferência sem gravá-la.
        if let override = ProcessInfo.processInfo.environment["WINEUP_DEFAULT_FOLDER"] {
            return URL(fileURLWithPath: override)
        }
        return UserDefaults.standard.string(forKey: defaultFolderKey).map { URL(fileURLWithPath: $0) }
    }

    static func loadFavorites() -> [URL] {
        (UserDefaults.standard.stringArray(forKey: favoritesKey) ?? []).map { URL(fileURLWithPath: $0) }
    }

    static func saveFavorites(_ urls: [URL]) {
        UserDefaults.standard.set(urls.map(\.path), forKey: favoritesKey)
    }

    static func displayPath(_ url: URL) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return url.path.hasPrefix(home) ? "~" + url.path.dropFirst(home.count) : url.path
    }
}

/// Navegação: a barra de cima escolhe a pasta; o visualizador escolhe como ver o que há nela.
final class LibraryBrowser: ObservableObject {
    @Published private(set) var folder: URL
    @Published private(set) var view: ViewMode
    @Published private(set) var group: ViewGroup?
    @Published private(set) var groups: [ViewGroup] = []
    @Published private(set) var subfolders: [URL] = []
    @Published private(set) var isLoading = false
    @Published private(set) var playlists: [UserPlaylist] = []
    @Published var favorites: [URL] = NavPlaces.loadFavorites()
    @Published var showColorTags: Bool {
        didSet { UserDefaults.standard.set(showColorTags, forKey: DisplayKeys.showColorTags); if view == .playlists { load() } }
    }
    @Published private(set) var backStack: [NavEntry] = []
    @Published private(set) var forwardStack: [NavEntry] = []

    /// Caminho → cor marcada pelo usuário.
    private(set) var marks: [String: MarkColor] = [:]
    /// Entrega a lista de faixas a mostrar (título, faixas).
    var onShowTracks: ((String, [Track]) -> Void)?
    /// Recarga automática (varredura/vigia): não deve substituir uma lista aberta à mão.
    private(set) var isBackgroundRefresh = false
    /// Fila atual (fornecida pelo player) para a visão "Fila".
    var queueProvider: (() -> [Track])?
    /// Pedido de nova varredura da biblioteca (botão Atualizar).
    var onRescan: (() -> Void)?

    private let database: LibraryDatabase?
    private var scopeCache: [String: [Track]] = [:]
    private let cacheLock = NSLock()
    private var loadToken = 0

    init(database: LibraryDatabase?) {
        self.database = database
        let defaults = UserDefaults.standard
        folder = NavPlaces.defaultFolder ?? NavPlaces.music
        view = ViewMode(rawValue: defaults.string(forKey: DisplayKeys.viewMode) ?? "") ?? .songs
        showColorTags = defaults.object(forKey: DisplayKeys.showColorTags) as? Bool ?? true
        refreshMarks()
    }

    var isAvailable: Bool { database != nil }
    private var collections: CollectionsStore? { database.map(CollectionsStore.init(database:)) }
    private var entry: NavEntry { NavEntry(folder: folder, view: view, groupID: group?.id) }

    /// Mostra grupos (álbuns, artistas...) em vez de faixas.
    var showsGroups: Bool { view.isGrouping && group == nil }

    // MARK: Navegação

    func go(folder newFolder: URL) {
        guard newFolder.standardizedFileURL != folder.standardizedFileURL else { load(); return }
        push()
        folder = newFolder.standardizedFileURL
        group = nil
        load()
    }

    func setView(_ newView: ViewMode) {
        UserDefaults.standard.set(newView.rawValue, forKey: DisplayKeys.viewMode)
        guard newView != view || group != nil else { return }
        push()
        view = newView
        group = nil
        load()
    }

    func open(_ newGroup: ViewGroup) {
        isBackgroundRefresh = false
        push()
        group = newGroup
        showGroupTracks(newGroup)
    }

    /// Fecha o grupo aberto (volta para a lista de álbuns/artistas...).
    func closeGroup() {
        guard group != nil else { return }
        push()
        group = nil
        load()
    }

    var canGoUp: Bool { group != nil || folder.path != "/" }

    func goUp() {
        if group != nil { closeGroup() }
        else if folder.path != "/" { go(folder: folder.deletingLastPathComponent().standardizedFileURL) }
    }

    func goBack() {
        guard let previous = backStack.popLast() else { return }
        forwardStack.append(entry)
        apply(previous)
    }

    func goForward() {
        guard let next = forwardStack.popLast() else { return }
        backStack.append(entry)
        apply(next)
    }

    private func push() {
        backStack.append(entry)
        forwardStack = []
    }

    private func apply(_ target: NavEntry) {
        folder = target.folder
        view = target.view
        group = nil
        load(reopening: target.groupID)
    }

    func refresh() {
        onRescan?()
        clearCache()
        refreshMarks()
        load(reopening: group?.id)
    }

    /// A biblioteca terminou uma varredura: recarrega o que está aberto.
    func libraryChanged() {
        clearCache()
        refreshMarks()
        load(reopening: group?.id, background: true)
    }

    // MARK: Pasta padrão

    var defaultFolder: URL { NavPlaces.defaultFolder ?? NavPlaces.music }

    func setDefaultFolder(_ url: URL) {
        UserDefaults.standard.set(url.standardizedFileURL.path, forKey: NavPlaces.defaultFolderKey)
        go(folder: url)
    }

    func chooseOtherFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.directoryURL = folder
        panel.message = "Escolha uma pasta para ver"
        if panel.runModal() == .OK, let url = panel.url { go(folder: url) }
    }

    func goToTypedPath() {
        guard let typed = TextPrompt.ask(title: "Ir para a pasta", value: NavPlaces.displayPath(folder)) else { return }
        let path = (typed.trimmingCharacters(in: .whitespaces) as NSString).expandingTildeInPath
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue {
            go(folder: URL(fileURLWithPath: path))
        } else {
            NSSound.beep()
        }
    }

    // MARK: Favoritos

    var isCurrentFavorite: Bool { favorites.contains(folder) }

    func toggleFavorite() { isCurrentFavorite ? removeFavorite(folder) : addFavorite(folder) }

    func addFavorite(_ url: URL) {
        guard !favorites.contains(url) else { return }
        favorites = favorites + [url]
        NavPlaces.saveFavorites(favorites)
    }

    func removeFavorite(_ url: URL) {
        favorites = favorites.filter { $0 != url }
        NavPlaces.saveFavorites(favorites)
    }

    // MARK: Carga

    func load(reopening groupID: String? = nil, background: Bool = false) {
        loadToken += 1
        isBackgroundRefresh = background
        if view == .queue {
            isLoading = false
            groups = []
            subfolders = []
            onShowTracks?("Fila", queueProvider?() ?? [])
            return
        }
        let token = loadToken
        let folder = folder, view = view, showTags = showColorTags
        isLoading = true
        let started = ProcessInfo.processInfo.systemUptime
        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            let result = self.build(folder: folder, view: view, showTags: showTags)
            await MainActor.run {
                guard token == self.loadToken else { return }
                PerfLog.record("load \(view.rawValue)", since: started,
                               detail: "\(result.tracks.count) faixas, \(result.groups.count) grupos")
                self.isLoading = false
                self.subfolders = result.subfolders
                self.groups = result.groups
                self.playlists = result.playlists
                if let groupID, let reopened = result.groups.first(where: { $0.id == groupID }) {
                    self.group = reopened
                    self.showGroupTracks(reopened)
                } else if !view.isGrouping {
                    self.onShowTracks?(view == .files ? Self.name(of: folder) : "Músicas", result.tracks)
                }
            }
        }
    }

    private struct Built {
        var tracks: [Track] = []
        var groups: [ViewGroup] = []
        var subfolders: [URL] = []
        var playlists: [UserPlaylist] = []
    }

    private func build(folder: URL, view: ViewMode, showTags: Bool) -> Built {
        var built = Built()
        built.playlists = (try? collections?.playlists()) ?? []
        switch view {
        case .files:
            let listing = Self.listFolder(folder)
            built.subfolders = listing.folders
            built.tracks = listing.tracks.map(withMark)
        case .songs:
            built.tracks = scope(folder)
        case .albums:
            built.groups = Self.albums(scope(folder))
        case .artists:
            built.groups = Self.grouped(scope(folder), key: { $0.artist }, empty: "Artista desconhecido")
        case .genres:
            built.groups = Self.grouped(scope(folder), key: { $0.genre }, empty: BrowseService.uncategorizedGenre)
        case .playlists:
            built.groups = playlistGroups(built.playlists, showTags: showTags)
        case .queue:
            break
        }
        return built
    }

    private func showGroupTracks(_ g: ViewGroup) { onShowTracks?(g.title, tracks(for: g)) }

    /// Todas as faixas dentro da pasta (com subpastas): do banco quando a pasta está
    /// indexada; senão, lidas do disco.
    private func scope(_ folder: URL) -> [Track] {
        let key = folder.standardizedFileURL.path
        cacheLock.lock()
        let cached = scopeCache[key]
        cacheLock.unlock()
        if let cached { return cached }
        let roots = (try? collections?.rootPaths()) ?? []
        let indexed = roots.contains { key == $0 || key.hasPrefix($0.hasSuffix("/") ? $0 : $0 + "/") }
        let tracks: [Track]
        if indexed, let collections {
            tracks = ((try? collections.tracks(under: key)) ?? []).map(track(from:))
        } else {
            tracks = TrackLoader.audioURLs(in: [folder]).prefix(3000).map { withMark(TrackLoader.track(url: $0)) }
        }
        cacheLock.lock()
        scopeCache[key] = tracks
        cacheLock.unlock()
        return tracks
    }

    private func clearCache() {
        cacheLock.lock()
        scopeCache = [:]
        cacheLock.unlock()
    }

    func track(from item: LibraryTrack) -> Track {
        Track(id: TrackID(stableKey: item.mediaPath == nil ? item.url.standardizedFileURL.path : item.path),
              artist: item.artist, title: item.title, duration: Int(item.duration ?? 0),
              mark: marks[item.path], url: item.url, album: item.album, genre: item.genre,
              start: item.start, end: item.end, libraryPath: item.mediaPath == nil ? nil : item.path)
    }

    private func withMark(_ t: Track) -> Track {
        var copy = t
        copy.mark = t.storeKey.flatMap { marks[$0] }
        return copy
    }

    // MARK: Agrupamentos

    /// Álbuns da pasta; faixas sem álbum ou de álbum com uma faixa vão para "Singles".
    private static func albums(_ tracks: [Track]) -> [ViewGroup] {
        func albumKey(_ t: Track) -> String? {
            guard let a = t.album?.trimmingCharacters(in: .whitespaces), !a.isEmpty, a != "Unknown Album" else { return nil }
            return a
        }
        let byAlbum = Dictionary(grouping: tracks.filter { albumKey($0) != nil }) { albumKey($0)! }
        var singles = tracks.filter { albumKey($0) == nil }
        var groups: [ViewGroup] = []
        for (name, items) in byAlbum {
            if items.count == 1 { singles += items; continue }
            let artists = Set(items.map(\.artist))
            groups.append(ViewGroup(id: "album:" + name, title: name,
                                    subtitle: artists.count == 1 ? items[0].artist : "Vários artistas",
                                    count: items.count, tracks: items, coverURL: items.first?.url))
        }
        groups.sort { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        if !singles.isEmpty {
            groups.insert(ViewGroup(id: "album:singles", title: BrowseService.singlesTitle,
                                    subtitle: "Faixas sem álbum ou de álbum com uma música",
                                    count: singles.count, tracks: singles, coverURL: singles.first?.url), at: 0)
        }
        return groups
    }

    private static func grouped(_ tracks: [Track], key: (Track) -> String?, empty: String) -> [ViewGroup] {
        let byKey = Dictionary(grouping: tracks) { t -> String in
            let k = key(t)?.trimmingCharacters(in: .whitespaces) ?? ""
            return k.isEmpty || k == "Unknown Artist" ? empty : k
        }
        return byKey.map { name, items in
            ViewGroup(id: "group:" + name, title: name, subtitle: "", count: items.count,
                      tracks: items, coverURL: items.first?.url)
        }
        .sorted { a, b in
            if a.title == empty { return false }
            if b.title == empty { return true }
            return a.title.localizedStandardCompare(b.title) == .orderedAscending
        }
    }

    private func playlistGroups(_ lists: [UserPlaylist], showTags: Bool) -> [ViewGroup] {
        var groups = lists.map {
            ViewGroup(id: "playlist:\($0.id)", title: $0.name, subtitle: "Sua playlist",
                      count: $0.paths.count, playlistID: $0.id)
        }
        if showTags {
            let counts = (try? collections?.markCounts()) ?? [:]
            let tags = MarkColor.allCases.compactMap { color -> ViewGroup? in
                guard let n = counts[color.rawValue], n > 0 else { return nil }
                return ViewGroup(id: "tag:" + color.rawValue, title: "Tag \(color.displayName)",
                                 subtitle: "Faixas marcadas com essa cor", count: n, color: color)
            }
            groups = tags + groups
        }
        return groups
    }

    // MARK: Disco

    static func name(of url: URL) -> String { url.lastPathComponent.isEmpty ? "/" : url.lastPathComponent }

    private static func listFolder(_ url: URL) -> (folders: [URL], tracks: [Track]) {
        let items = (try? FileManager.default.contentsOfDirectory(
            at: url, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])) ?? []
        let allowed = TrackLoader.supportedExtensions
        let folders = items.filter {
            (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true && $0.pathExtension != "app"
        }
        .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
        // Folhas CUE: viram faixas virtuais e escondem o arquivo único que elas dividem.
        let cueTracks = items.filter { $0.pathExtension.lowercased() == "cue" }
            .sorted { $0.path < $1.path }
            .flatMap(cueTracksFor)
        let covered = Set(cueTracks.compactMap { $0.url?.standardizedFileURL.path })
        let files = items.filter { allowed.contains($0.pathExtension.lowercased()) && !covered.contains($0.standardizedFileURL.path) }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
            .prefix(2000)
        return (folders, cueTracks + files.map(TrackLoader.track(url:)))
    }


    /// Faixas de uma folha CUE (o arquivo de áudio precisa existir).
    private static func cueTracksFor(_ cueURL: URL) -> [Track] {
        guard let data = try? Data(contentsOf: cueURL),
              let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1),
              let sheet = CueSheet.parse(text, baseDirectory: cueURL.deletingLastPathComponent()) else { return [] }
        var fileDurations: [URL: Double] = [:]
        return sheet.entries.compactMap { entry in
            guard FileManager.default.fileExists(atPath: entry.file.path) else { return nil }
            let total = fileDurations[entry.file] ?? Double(TrackLoader.track(url: entry.file).duration)
            fileDurations[entry.file] = total
            let length = (entry.end ?? total) - entry.start
            // Mesma chave do índice (CueIndexer): "<arquivo.cue>#<n>".
            let key = cueURL.standardizedFileURL.path + "#\(entry.number)"
            return Track(id: TrackID(stableKey: key),
                         artist: entry.performer, title: entry.title, duration: Int(max(length, 0).rounded()),
                         mark: nil, url: entry.file, album: sheet.album, start: entry.start, end: entry.end,
                         libraryPath: key)
        }
    }

    // MARK: Marcações e playlists

    func refreshMarks() {
        let raw = (try? collections?.marks()) ?? [:]
        marks = raw.compactMapValues(MarkColor.init(rawValue:))
    }

    func mark(for url: URL?) -> MarkColor? { url.flatMap { marks[$0.path] } }

    func setMark(_ color: MarkColor?, path: String) {
        _ = try? collections?.setMark(path: path, color: color?.rawValue)
        refreshMarks()
        clearCache()
        if view == .playlists { load(reopening: group?.id) }
    }

    @discardableResult
    func createPlaylist(named name: String, paths: [String] = []) -> UserPlaylist? {
        guard let collections, let created = try? collections.createPlaylist(named: name) else { return nil }
        if !paths.isEmpty { _ = try? collections.append(paths: paths, toPlaylist: created.id) }
        playlists = (try? collections.playlists()) ?? playlists
        if view == .playlists { load(reopening: group?.id) }
        return created
    }

    func renamePlaylist(id: Int64, to name: String) {
        try? collections?.renamePlaylist(id: id, to: name)
        load(reopening: group?.id)
    }

    func deletePlaylist(id: Int64) {
        try? collections?.deletePlaylist(id: id)
        if group?.playlistID == id { group = nil }
        load()
    }

    func add(paths: [String], toPlaylist id: Int64) {
        _ = try? collections?.append(paths: paths, toPlaylist: id)
        if view == .playlists { load(reopening: group?.id) }
    }

    var openPlaylistID: Int64? { group?.playlistID }

    func remove(path: String, fromPlaylist id: Int64) {
        try? collections?.remove(path: path, fromPlaylist: id)
        load(reopening: group?.id)
    }

    /// Faixa por caminho: do banco (se indexada) ou lida do arquivo.
    func track(atPath path: String) -> Track {
        if let item = try? collections?.track(atPath: path) { return track(from: item) }
        return withMark(TrackLoader.track(url: URL(fileURLWithPath: path)))
    }

    /// Faixas de um grupo (playlists e tags vêm do banco).
    func tracks(for g: ViewGroup) -> [Track] {
        if let id = g.playlistID { return ((try? collections?.tracks(inPlaylist: id)) ?? []).map(track(from:)) }
        if let color = g.color { return ((try? collections?.tracks(markedWith: color.rawValue)) ?? []).map(track(from:)) }
        return g.tracks
    }

    /// A pasta já está dentro de uma raiz da biblioteca?
    func isIndexed(_ url: URL) -> Bool {
        let key = url.standardizedFileURL.path
        let roots = (try? collections?.rootPaths()) ?? []
        return roots.contains { key == $0 || key.hasPrefix($0.hasSuffix("/") ? $0 : $0 + "/") }
    }

    func allPlaylists() -> [UserPlaylist] { (try? collections?.playlists()) ?? [] }

    func resolvePath(path: String, title: String, artist: String) -> String? {
        (try? collections?.resolvePath(path: path, title: title, artist: artist)) ?? nil
    }
}

/// Ações de caminho compartilhadas (copiar, Finder).
enum PathActions {
    static func copy(_ url: URL) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url.path, forType: .string)
    }

    static func reveal(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}

/// Medição opcional: WINEUP_PERF_LOG=<arquivo> grava a duração das cargas de visão.
enum PerfLog {
    private static let path = ProcessInfo.processInfo.environment["WINEUP_PERF_LOG"]

    static func record(_ name: String, since start: TimeInterval, detail: String = "") {
        guard let path else { return }
        let ms = (ProcessInfo.processInfo.systemUptime - start) * 1000
        let line = String(format: "%@\t%.1f ms\t%@\n", name, ms, detail)
        if let handle = FileHandle(forWritingAtPath: path) {
            handle.seekToEndOfFile()
            handle.write(Data(line.utf8))
            try? handle.close()
        } else {
            FileManager.default.createFile(atPath: path, contents: Data(line.utf8))
        }
    }
}
