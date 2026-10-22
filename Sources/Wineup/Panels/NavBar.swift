import SwiftUI

/// Barra de cima: escolhe a PASTA (pasta padrão, locais, favoritos, caminho clicável).
struct NavBar: View {
    @ObservedObject var state: PlayerState
    @ObservedObject var browser: LibraryBrowser
    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: 10) {
            locationMenu
            Divider().frame(height: 18)
            Image(systemName: isDefault(browser.folder) ? "house" : "folder")
                .foregroundStyle(theme.mutedText)
            breadcrumb
            Spacer(minLength: 4)
            Button { browser.toggleFavorite() } label: {
                Image(systemName: browser.isCurrentFavorite ? "star.fill" : "star")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(browser.isCurrentFavorite ? Color.yellow : theme.mutedText)
            .help(browser.isCurrentFavorite ? "Remover dos favoritos" : "Adicionar aos favoritos")
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

    private func isDefault(_ url: URL) -> Bool { url.standardizedFileURL == browser.defaultFolder.standardizedFileURL }

    // MARK: Seletor de local

    private var rootName: String {
        let path = browser.folder.path
        if path.hasPrefix(browser.defaultFolder.path) { return LibraryBrowser.name(of: browser.defaultFolder) }
        if path.hasPrefix(NavPlaces.downloads.path) { return "Downloads" }
        return LibraryBrowser.name(of: browser.folder)
    }

    private var locationMenu: some View {
        Menu {
            Section("Caminho") {
                ForEach(Self.ancestors(of: browser.folder), id: \.self) { item in
                    Button { browser.go(folder: item) } label: {
                        Label(item.path == "/" ? "Macintosh HD" : item.lastPathComponent,
                              systemImage: isDefault(item) ? "house" : "folder")
                    }
                }
            }
            Section("Locais") {
                Button { browser.go(folder: browser.defaultFolder) } label: {
                    Label("Pasta padrão (\(LibraryBrowser.name(of: browser.defaultFolder)))", systemImage: "house")
                }
                Button { browser.go(folder: NavPlaces.music) } label: { Label("Música", systemImage: "music.note") }
                Button { browser.go(folder: NavPlaces.downloads) } label: { Label("Downloads", systemImage: "arrow.down.circle") }
            }
            if !browser.favorites.isEmpty {
                Section("Favoritos") {
                    ForEach(browser.favorites, id: \.self) { url in
                        Button { browser.go(folder: url) } label: { Label(url.lastPathComponent, systemImage: "star") }
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
            Button("Usar esta pasta como padrão") { state.makeDefaultFolder(browser.folder) }
                .disabled(isDefault(browser.folder))
        } label: {
            Label(rootName, systemImage: browser.folder.path.hasPrefix(browser.defaultFolder.path) ? "house" : "folder")
                .labelStyle(.titleAndIcon)
        }
        .menuStyle(.button)
        .buttonStyle(.bordered)
        .controlSize(.small)
        .fixedSize()
    }

    private static func ancestors(of url: URL) -> [URL] {
        var list: [URL] = []
        var current = url.standardizedFileURL
        // Para na raiz: em "/", deletingLastPathComponent devolve "/..", que nunca termina.
        while list.count < 64 {
            list.append(current)
            if current.path == "/" { break }
            current = current.deletingLastPathComponent().standardizedFileURL
        }
        return list
    }

    // MARK: Mais ações

    private var actionsMenu: some View {
        Menu {
            Button("Copiar caminho") { PathActions.copy(browser.folder) }
            Button("Mostrar no Finder") { PathActions.reveal(browser.folder) }
            Button("Tocar tudo desta pasta") { state.playFolder(browser.folder) }
            Button("Adicionar à biblioteca") { state.load(urls: [browser.folder]) }
            Divider()
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

    // MARK: Caminho clicável (a partir da pasta padrão, ou da pasta pessoal)

    var crumbs: [(title: String, url: URL)] {
        let base = browser.folder.path.hasPrefix(browser.defaultFolder.path)
            ? browser.defaultFolder.standardizedFileURL
            : FileManager.default.homeDirectoryForCurrentUser
        var parts: [URL] = []
        var current = browser.folder.standardizedFileURL
        while current.path.count >= base.path.count, parts.count < 64 {
            parts.insert(current, at: 0)
            if current.path == base.path || current.path == "/" { break }
            current = current.deletingLastPathComponent().standardizedFileURL
        }
        if parts.isEmpty { parts = [browser.folder] }
        return parts.suffix(4).map { url in
            (url.path == FileManager.default.homeDirectoryForCurrentUser.path ? "~" : LibraryBrowser.name(of: url), url)
        }
    }

    private var breadcrumb: some View {
        HStack(spacing: 3) {
            ForEach(Array(crumbs.enumerated()), id: \.offset) { index, crumb in
                if index > 0 {
                    Image(systemName: "chevron.right").font(.system(size: 8)).foregroundStyle(theme.mutedText)
                }
                Button(crumb.title) { browser.go(folder: crumb.url) }
                    .buttonStyle(.plain)
                    .foregroundStyle(index == crumbs.count - 1 ? theme.text : theme.mutedText)
                    .lineLimit(1)
                    .contextMenu {
                        Button("Abrir") { browser.go(folder: crumb.url) }
                        Button("Copiar caminho") { PathActions.copy(crumb.url) }
                        Button("Mostrar no Finder") { PathActions.reveal(crumb.url) }
                    }
            }
        }
        .lineLimit(1)
        .layoutPriority(-1)
    }
}
