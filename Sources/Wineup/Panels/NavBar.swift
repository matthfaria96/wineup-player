import SwiftUI

/// Barra de navegação no estilo do Finder: subir, seletor de local, caminho clicável e busca.
struct NavBar: View {
    @ObservedObject var state: PlayerState
    @ObservedObject var browser: LibraryBrowser
    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: 6) {
            Button { browser.goUp() } label: {
                Image(systemName: "arrow.up").frame(width: 18, height: 18)
            }
            .buttonStyle(.borderless)
            .disabled(!browser.canGoUp)
            .help("Subir um nível")

            locationMenu
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
            searchField
        }
        .font(.system(size: 12))
        .foregroundStyle(theme.text)
        .padding(.horizontal, 10)
        .frame(height: 28)
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
            Label(currentName, systemImage: currentIcon).labelStyle(.titleAndIcon)
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
                Button { } label: { Label(group, systemImage: browser.mode.symbol) }
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
                    .foregroundStyle(index == crumbs.count - 1 ? theme.text : theme.mutedText)
                    .lineLimit(1)
            }
        }
        .lineLimit(1)
        .truncationMode(.head)
        .layoutPriority(-1)
    }

    private struct Crumb { let title: String; let action: () -> Void }

    private var crumbs: [Crumb] {
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
                Crumb(title: item.path == home.path ? "~" : item.lastPathComponent) { browser.goFolder(item) }
            }
        case .library:
            var list = [Crumb(title: "Biblioteca") { browser.goLibrary(browser.mode) },
                        Crumb(title: browser.mode.title) { browser.goLibrary(browser.mode) }]
            if let group = browser.currentGroupTitle { list.append(Crumb(title: group) {}) }
            return list
        }
    }

    // MARK: Busca

    private var searchField: some View {
        HStack(spacing: 4) {
            Image(systemName: "magnifyingglass").foregroundStyle(theme.mutedText)
            TextField("Buscar", text: $state.query).textFieldStyle(.plain)
            if !state.query.isEmpty {
                Image(systemName: "xmark.circle.fill").foregroundStyle(theme.mutedText)
                    .onTapGesture { state.query = "" }
            }
        }
        .padding(.horizontal, 6)
        .frame(width: 130, height: 22)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.06)))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(theme.panelBorder, lineWidth: 1))
    }
}
