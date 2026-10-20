import Foundation
import WineupCore
import WineupLibrary

/// Estado da navegação da biblioteca: visão escolhida, itens da coluna, marcações de cor e playlists.
final class LibraryBrowser: ObservableObject {
    @Published var mode: BrowseMode {
        didSet { UserDefaults.standard.set(mode.rawValue, forKey: DisplayKeys.browseMode); reload() }
    }
    @Published var showColorTags: Bool {
        didSet { UserDefaults.standard.set(showColorTags, forKey: DisplayKeys.showColorTags); reload() }
    }
    @Published private(set) var groups: [BrowseGroup] = []
    @Published var selected: BrowseGroup.Kind?
    @Published private(set) var playlists: [UserPlaylist] = []
    @Published private(set) var isLoading = false
    /// `true` mostra a lista de álbuns/bandas/pastas/estilos/playlists; `false` mostra as faixas abertas.
    @Published var showingGroups = false
    /// Onde o usuário está: na biblioteca (por álbum, banda...) ou numa pasta do disco.
    @Published var location: NavLocation = .library
    @Published var subfolders: [URL] = []
    @Published var favorites: [URL] = NavPlaces.loadFavorites()
    @Published var currentGroupTitle: String?
    var onOpenTracks: ((String, [Track]) -> Void)?
    /// Pedido de nova varredura da biblioteca (botão Atualizar).
    var onRefresh: (() -> Void)?
    /// Histórico para os botões voltar/avançar.
    @Published var backStack: [NavEntry] = []
    @Published var forwardStack: [NavEntry] = []
    var currentEntry: NavEntry?
    var isReplaying = false

    /// Caminho → cor marcada pelo usuário.
    private(set) var marks: [String: MarkColor] = [:]

    private let database: LibraryDatabase?
    /// Entrega as faixas do grupo aberto (título do grupo, faixas da biblioteca).
    var onOpen: ((String, [LibraryTrack]) -> Void)?
    private var loadTask: Task<Void, Never>?

    init(database: LibraryDatabase?) {
        self.database = database
        let defaults = UserDefaults.standard
        let savedMode = BrowseMode(rawValue: defaults.string(forKey: DisplayKeys.browseMode) ?? "") ?? .albums
        // "Pastas" agora é navegação no disco (barra de navegação), não uma visão da biblioteca.
        mode = savedMode == .folders ? .albums : savedMode
        showColorTags = defaults.object(forKey: DisplayKeys.showColorTags) as? Bool ?? true
        refreshMarks()
    }

    var isAvailable: Bool { database != nil }

    private var collections: CollectionsStore? { database.map(CollectionsStore.init(database:)) }

    // MARK: Coluna de navegação

    func reload() {
        guard let database else { groups = []; return }
        loadTask?.cancel()
        let mode = mode
        let showColorTags = showColorTags
        isLoading = true
        loadTask = Task { [weak self] in
            let built = await Self.buildGroups(mode: mode, showColorTags: showColorTags, database: database)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self else { return }
                self.groups = built.groups
                self.playlists = built.playlists
                self.isLoading = false
            }
        }
    }

    private static func buildGroups(mode: BrowseMode, showColorTags: Bool,
                                    database: LibraryDatabase) async -> (groups: [BrowseGroup], playlists: [UserPlaylist]) {
        let browse = BrowseService(database: database)
        let collections = CollectionsStore(database: database)
        switch mode {
        case .albums:
            let albums = (try? await browse.albums()) ?? []
            // Álbuns com uma única faixa vão para "Singles" (agrupamento virtual, sem regravar tags).
            let real = albums.filter { $0.trackCount > 1 && $0.title != "Unknown Album" }
            var groups = real.map {
                BrowseGroup(kind: .album($0.id), title: $0.title,
                            subtitle: [$0.artist, $0.year].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "),
                            count: $0.trackCount)
            }
            if let singles = try? await browse.singlesSummary(), singles.trackCount > 0 {
                groups.insert(BrowseGroup(kind: .singles, title: BrowseService.singlesTitle,
                                          subtitle: "Faixas sem álbum ou de álbum com uma música",
                                          count: singles.trackCount), at: 0)
            }
            return (groups, [])
        case .artists:
            let artists = (try? await browse.artists()) ?? []
            return (artists.map { BrowseGroup(kind: .artist($0.id), title: $0.name, subtitle: "", count: $0.trackCount) }, [])
        case .folders:
            let folders = (try? collections.folders()) ?? []
            return (folders.map {
                let url = URL(fileURLWithPath: $0.path)
                return BrowseGroup(kind: .folder($0.path), title: url.lastPathComponent,
                                   subtitle: url.deletingLastPathComponent().path, count: $0.trackCount)
            }, [])
        case .genres:
            let genres = (try? await browse.genres()) ?? []
            return (genres.map { BrowseGroup(kind: .genre($0.name), title: $0.name, subtitle: "", count: $0.trackCount) }, [])
        case .playlists:
            let lists = (try? collections.playlists()) ?? []
            var groups = lists.map {
                BrowseGroup(kind: .playlist($0.id), title: $0.name, subtitle: "Sua playlist", count: $0.paths.count)
            }
            if showColorTags {
                let counts = (try? collections.markCounts()) ?? [:]
                // Só aparecem cores com ao menos uma faixa marcada.
                let tagGroups = MarkColor.allCases.compactMap { color -> BrowseGroup? in
                    guard let n = counts[color.rawValue], n > 0 else { return nil }
                    return BrowseGroup(kind: .colorTag(color), title: "Tag \(color.displayName)",
                                       subtitle: "Faixas marcadas com essa cor", count: n)
                }
                groups = tagGroups + groups
            }
            return (groups, lists)
        }
    }

    /// Abre um grupo: carrega as faixas dele e entrega ao player.
    func open(_ group: BrowseGroup) {
        guard let database else { return }
        selected = group.kind
        showingGroups = false
        location = .library
        currentGroupTitle = group.title
        record(.group(group))
        let kind = group.kind
        let title = group.title
        Task { [weak self] in
            let tracks = await Self.tracks(for: kind, database: database)
            await MainActor.run { self?.onOpen?(title, tracks) }
        }
    }

    private static func tracks(for kind: BrowseGroup.Kind, database: LibraryDatabase) async -> [LibraryTrack] {
        let browse = BrowseService(database: database)
        let collections = CollectionsStore(database: database)
        switch kind {
        case .album(let id): return (try? await browse.tracks(releaseID: id)) ?? []
        case .singles: return (try? await browse.singles()) ?? []
        case .artist(let id): return (try? await browse.tracks(artistID: id)) ?? []
        case .folder(let path): return (try? await browse.tracks(inFolder: path)) ?? []
        case .genre(let name): return (try? await browse.tracks(genre: name)) ?? []
        case .playlist(let id): return (try? collections.tracks(inPlaylist: id)) ?? []
        case .colorTag(let color): return (try? collections.tracks(markedWith: color.rawValue)) ?? []
        case .allTracks: return (try? await browse.allTracks(limit: 5000)) ?? []
        }
    }

    // MARK: Marcações de cor

    func refreshMarks() {
        let raw = (try? collections?.marks()) ?? [:]
        marks = raw.compactMapValues(MarkColor.init(rawValue:))
    }

    func mark(for url: URL?) -> MarkColor? {
        url.flatMap { marks[$0.path] }
    }

    func setMark(_ color: MarkColor?, path: String) {
        _ = try? collections?.setMark(path: path, color: color?.rawValue)
        refreshMarks()
        if mode == .playlists { reload() }
    }

    // MARK: Playlists

    @discardableResult
    func createPlaylist(named name: String, paths: [String] = []) -> UserPlaylist? {
        guard let collections, let created = try? collections.createPlaylist(named: name) else { return nil }
        if !paths.isEmpty { _ = try? collections.append(paths: paths, toPlaylist: created.id) }
        reload()
        return created
    }

    func renamePlaylist(id: Int64, to name: String) {
        try? collections?.renamePlaylist(id: id, to: name)
        reload()
    }

    func deletePlaylist(id: Int64) {
        try? collections?.deletePlaylist(id: id)
        if selected == .playlist(id) { selected = nil }
        reload()
    }

    func add(paths: [String], toPlaylist id: Int64) {
        _ = try? collections?.append(paths: paths, toPlaylist: id)
        reload()
    }

    func allPlaylists() -> [UserPlaylist] {
        (try? collections?.playlists()) ?? []
    }

    func resolvePath(path: String, title: String, artist: String) -> String? {
        (try? collections?.resolvePath(path: path, title: title, artist: artist)) ?? nil
    }
}
