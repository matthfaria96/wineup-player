import SwiftUI

/// Barra de navegação no estilo do Finder: subir, seletor de local, caminho clicável e busca.
struct NavBar: View {
    @ObservedObject var state: PlayerState
    @ObservedObject var browser: LibraryBrowser
    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: 10) {
            locationMenu
            Divider().frame(height: 18)
            Image(systemName: currentIcon).foregroundStyle(theme.mutedText)
            breadcrumb
            Spacer(minLength: 4)
            if browser.currentFolder != nil {
                Button { browser.toggleFavorite() } label: {
                    Image(systemName: browser.isCurrentFavorite ? "star.fill" : "star")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(browser.isCurrentFavorite ? Color.yellow : theme.mutedText)
                .help(browser.isCurrentFavorite ? "Remover dos favoritos" : "Adicionar aos favoritos")
            }
            actionsMenu
            Button { browser.refresh() } label: { Image(systemName: "arrow.clockwise") }
                .buttonStyle(.borderless)
                .foregroundStyle(theme.mutedText)
                .help("Atualizar")
        }
        .font(.system(size: 12))
        .foregroundStyle(theme.text)
        .padding(.horizontal, 12)
        .frame(height: 40)
    }

    /// Título grande, caminho e contagem acima da lista.
    var crumbTitles: [String] { crumbs.map(\.title) }

    /// Mais ações do local atual: copiar caminho, Finder, ir para pasta, biblioteca.
    private var actionsMenu: some View {
        Menu {
            if let url = browser.currentFolder {
                Button("Copiar caminho") { PathActions.copy(url) }
                Button("Mostrar no Finder") { PathActions.reveal(url) }
                Button("Tocar tudo desta pasta") { state.playFolder(url) }
                Button("Adicionar à biblioteca") { state.load(urls: [url]) }
                Divider()
            }
            Button("Ir para a pasta…") { browser.goToTypedPath() }
            Button("Escolher outra pasta…") { browser.chooseOtherFolder() }
            Button("Subir um nível") { browser.goUp() }.disabled(!browser.canGoUp)
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Mais ações")
    }

    // MARK: Seletor de local

    private var currentName: String {
        switch browser.location {
        case .folder(let url): return url.lastPathComponent.isEmpty ? "/" : url.lastPathComponent
        case .library: return browser.currentGroupTitle ?? browser.mode.title
        }
    }

    private var currentIcon: String {
        switch browser.location {
        case .folder: return "folder.fill"
        case .library: return browser.mode.symbol
        }
    }

    private var rootName: String {
        guard let url = browser.currentFolder else { return "Biblioteca" }
        if url.path.hasPrefix(NavPlaces.music.path) { return "Música" }
        if url.path.hasPrefix(NavPlaces.downloads.path) { return "Downloads" }
        return url.lastPathComponent.isEmpty ? "/" : url.lastPathComponent
    }

    private var rootIcon: String {
        guard let url = browser.currentFolder else { return "music.note.house" }
        if url.path.hasPrefix(NavPlaces.music.path) { return "music.note" }
        if url.path.hasPrefix(NavPlaces.downloads.path) { return "arrow.down.circle" }
        return "folder"
    }

    private var locationMenu: some View {
        Menu {
            Section("Caminho") { pathItems }
            Section("Locais") {
                Button { browser.goFolder(NavPlaces.music) } label: { Label("Música", systemImage: "music.note") }
                Button { browser.goLibrary(browser.mode == .folders ? .albums : browser.mode) } label: {
                    Label("Biblioteca", systemImage: "books.vertical")
                }
                Button { browser.goFolder(NavPlaces.downloads) } label: { Label("Downloads", systemImage: "arrow.down.circle") }
            }
            Section("Biblioteca por") {
                ForEach(BrowseMode.allCases.filter { $0 != .folders }) { mode in
                    Button { browser.goLibrary(mode) } label: { Label(mode.title, systemImage: mode.symbol) }
                }
            }
            if !browser.favorites.isEmpty {
                Section("Favoritos") {
                    ForEach(browser.favorites, id: \.self) { url in
                        Button { browser.goFolder(url) } label: { Label(url.lastPathComponent, systemImage: "star") }
                    }
                    Menu("Remover favorito") {
                        ForEach(browser.favorites, id: \.self) { url in
                            Button(NavPlaces.displayPath(url)) { browser.removeFavorite(url) }
                        }
                    }
                }
            }
            Divider()
            Button("Escolher outra pasta…") { browser.chooseOtherFolder() }
        } label: {
            Label(rootName, systemImage: rootIcon).labelStyle(.titleAndIcon)
        }
        .menuStyle(.button)
        .buttonStyle(.bordered)
        .controlSize(.small)
        .fixedSize()
    }

    @ViewBuilder private var pathItems: some View {
        switch browser.location {
        case .folder(let url):
            ForEach(Self.ancestors(of: url), id: \.self) { item in
                Button { browser.goFolder(item) } label: {
                    Label(item.lastPathComponent.isEmpty ? "Macintosh HD" : item.lastPathComponent, systemImage: "folder")
                }
            }
        case .library:
            if let group = browser.currentGroupTitle {
                Text(group)
            }
            Button { browser.goLibrary(browser.mode) } label: { Label(browser.mode.title, systemImage: browser.mode.symbol) }
            Button { browser.goLibrary(.albums) } label: { Label("Biblioteca", systemImage: "books.vertical") }
        }
    }

    private static func ancestors(of url: URL) -> [URL] {
        var list: [URL] = []
        var current = url
        while true {
            list.append(current)
            let parent = current.deletingLastPathComponent()
            if parent.path == current.path { break }
            current = parent
        }
        return list
    }

    // MARK: Caminho clicável

    private var breadcrumb: some View {
        HStack(spacing: 3) {
            ForEach(Array(crumbs.enumerated()), id: \.offset) { index, crumb in
                if index > 0 {
                    Image(systemName: "chevron.right").font(.system(size: 8)).foregroundStyle(theme.mutedText)
                }
                Button(crumb.title) { crumb.action() }
                    .buttonStyle(.plain)
                    .contextMenu {
                        if let url = crumb.url {
                            Button("Abrir") { browser.goFolder(url) }
                            Button("Copiar caminho") { PathActions.copy(url) }
                            Button("Mostrar no Finder") { PathActions.reveal(url) }
                        }
                    }
                    .foregroundStyle(index == crumbs.count - 1 ? theme.text : theme.mutedText)
                    .lineLimit(1)
            }
        }
        .lineLimit(1)
        .truncationMode(.head)
        .layoutPriority(-1)
    }

    struct Crumb {
        let title: String
        var url: URL? = nil
        let action: () -> Void
    }

    var crumbs: [Crumb] {
        switch browser.location {
        case .folder(let url):
            let home = FileManager.default.homeDirectoryForCurrentUser
            var parts: [URL] = []
            var current = url
            while current.path.count >= home.path.count, current.path != "/" {
                parts.insert(current, at: 0)
                if current.path == home.path { break }
                current = current.deletingLastPathComponent()
            }
            if parts.isEmpty { parts = [url] }
            return parts.suffix(3).map { item in
                Crumb(title: item.path == home.path ? "~" : item.lastPathComponent, url: item) { browser.goFolder(item) }
            }
        case .library:
            var list = [Crumb(title: "Biblioteca") { browser.goLibrary(browser.mode) }]
            if browser.selected == .allTracks || (browser.selected == nil && browser.currentGroupTitle != nil) {
                list.append(Crumb(title: "Todas as músicas") { browser.refresh() })
                return list
            }
            list.append(Crumb(title: browser.mode.title) { browser.goLibrary(browser.mode) })
            if !browser.showingGroups, let group = browser.currentGroupTitle {
                list.append(Crumb(title: group) { browser.refresh() })
            }
            return list
        }
    }

}
