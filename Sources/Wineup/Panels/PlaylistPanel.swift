import SwiftUI
import WineupCore

/// Playlist com a navegação da biblioteca embutida: grupos (álbuns, bandas...) ↔ faixas.
struct PlaylistPanel: View {
    @ObservedObject var state: PlayerState
    @ObservedObject var browser: LibraryBrowser
    @Environment(\.theme) private var theme

    var body: some View {
        let nav = NavBar(state: state, browser: browser)
        Panel(title: "") {
            VStack(spacing: 0) {
                nav
                Divider().opacity(0.5)
                titleBlock(crumbs: nav.crumbTitles)
                if showsColumns { columnHeader }
                Group {
                    if !state.query.isEmpty {
                        trackList(state.searchResults)
                    } else if showingGroups {
                        LibraryGroupsView(state: state, browser: browser)
                    } else {
                        trackList(state.visibleTracks)
                    }
                }
                .frame(maxHeight: .infinity)
                footer
            }
        }
    }

    private var showingGroups: Bool { browser.location == .library && browser.showingGroups && state.query.isEmpty }
    private var showsColumns: Bool { !showingGroups && state.listStyle != .grid }

    private var bigTitle: String {
        if !state.query.isEmpty { return "Busca" }
        return showingGroups ? browser.mode.title : state.listTitle
    }

    private func titleBlock(crumbs: [String]) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 3) {
                if browser.location == .library && state.query.isEmpty {
                    Menu {
                        ForEach(BrowseMode.allCases.filter { $0 != .folders }) { mode in
                            Button { browser.goLibrary(mode) } label: { Label(mode.title, systemImage: mode.symbol) }
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Text(bigTitle).font(.system(size: 24, weight: .bold)).lineLimit(1)
                            Image(systemName: "chevron.down").font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(theme.mutedText)
                        }
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .help("Ver biblioteca por")
                } else {
                    Text(bigTitle).font(.system(size: 24, weight: .bold)).lineLimit(1)
                }
                Text(state.query.isEmpty ? crumbs.joined(separator: " / ") : "Resultados para \u{201C}\(state.query)\u{201D}")
                    .font(.system(size: 12)).foregroundStyle(theme.mutedText).lineLimit(1)
            }
            Spacer(minLength: 8)
            Text(countText).font(.system(size: 12)).foregroundStyle(theme.mutedText)
        }
        .foregroundStyle(theme.text)
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 10)
    }

    private var countText: String {
        if showingGroups { return "\(browser.groups.count) itens" }
        let n = state.query.isEmpty ? state.visibleTracks.count : state.searchResults.count
        return "\(n) faixas"
    }

    private var columnHeader: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text("#").frame(width: 28, alignment: .trailing)
                Text("Título — Artista")
                Spacer()
                Text("Duração").frame(width: 60, alignment: .trailing)
            }
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(theme.mutedText)
            .padding(.horizontal, 14)
            .frame(height: 24)
            Divider().opacity(0.4).padding(.horizontal, 10)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "music.note.list").font(.system(size: 28)).foregroundStyle(theme.mutedText)
            Text(state.query.isEmpty ? "Nenhuma música aqui" : "Nada encontrado")
                .font(.system(size: 13, weight: .semibold))
            Text("Abra uma pasta (⌘O), arraste músicas para a janela ou escolha outro local em Biblioteca ▾.")
                .font(.system(size: 11)).foregroundStyle(theme.mutedText)
                .multilineTextAlignment(.center).frame(maxWidth: 280)
        }
        .foregroundStyle(theme.text)
        .padding(.top, 40)
    }

    /// Subpastas da pasta atual, antes das músicas.
    @ViewBuilder private var folderRows: some View {
        if browser.currentFolder != nil, state.query.isEmpty {
            ForEach(browser.subfolders, id: \.self) { url in
                HStack(spacing: 8) {
                    Image(systemName: "folder.fill").foregroundStyle(theme.accent.opacity(0.8)).frame(width: 28)
                    Text(url.lastPathComponent).lineLimit(1)
                    Spacer()
                    Image(systemName: "chevron.right").font(.system(size: 9)).foregroundStyle(theme.mutedText)
                }
                .font(.system(size: 13))
                .foregroundStyle(theme.text)
                .padding(.horizontal, 10)
                .frame(height: 24)
                .contentShape(Rectangle())
                .onTapGesture { browser.goFolder(url) }
                .contextMenu { FolderMenu(state: state, browser: browser, url: url) }
            }
        }
    }

    private func trackList(_ tracks: [Track]) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                if state.listStyle == .grid {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 8)], spacing: 8) {
                        ForEach(tracks) { track in
                            TrackTile(track: track, isCurrent: track.id == state.currentID)
                                .id(track.id)
                                .onTapGesture(count: 2) { state.play(track) }
                                .contextMenu { TrackMenu(state: state, track: track) }
                        }
                    }
                    .padding(8)
                } else {
                    LazyVStack(spacing: 0) {
                        folderRows
                        if tracks.isEmpty && browser.subfolders.isEmpty || tracks.isEmpty && browser.currentFolder == nil {
                            emptyState
                        }
                        ForEach(Array(tracks.enumerated()), id: \.element.id) { offset, track in
                            TrackRow(track: track, index: offset + 1,
                                     isCurrent: track.id == state.currentID,
                                     isSelected: track.id == state.selectedID,
                                     detailed: state.listStyle == .detailed)
                                .id(track.id)
                                .onTapGesture(count: 2) { state.play(track) }
                                .onTapGesture { state.selectedID = track.id }
                                .contextMenu { TrackMenu(state: state, track: track) }
                        }
                    }
                }
            }
            .onAppear { if let id = state.currentID { proxy.scrollTo(id, anchor: .center) } }
        }
    }

    private var footer: some View {
        HStack(spacing: 6) {
            ColorDots(selection: $state.markFilter)
                .help("Filtrar por tag de cor")
            Spacer(minLength: 0)
            Picker("Estilo da lista", selection: $state.listStyle) {
                Image(systemName: "list.bullet").help("Compacta").tag(ListStyle.compact)
                Image(systemName: "list.bullet.rectangle").help("Com detalhes").tag(ListStyle.detailed)
                Image(systemName: "square.grid.2x2").help("Grade").tag(ListStyle.grid)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .controlSize(.small)
            .fixedSize()
            Menu {
                ForEach(Theme.all) { theme in
                    Button(theme.name) { UserDefaults.standard.set(theme.id, forKey: DisplayKeys.theme) }
                }
            } label: {
                Image(systemName: "paintpalette")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Tema")
        }
        .padding(.horizontal, 14)
        .frame(height: 34)
        .overlay(alignment: .top) { Divider().opacity(0.5) }
    }
}

/// Ações de uma pasta: abrir, copiar caminho, Finder, favoritos, biblioteca.
struct FolderMenu: View {
    let state: PlayerState
    let browser: LibraryBrowser
    let url: URL

    var body: some View {
        Button("Abrir") { browser.goFolder(url) }
        Button("Tocar tudo") { state.playFolder(url) }
        Divider()
        Button("Copiar caminho") { PathActions.copy(url) }
        Button("Mostrar no Finder") { PathActions.reveal(url) }
        Divider()
        Button(browser.favorites.contains(url) ? "Remover dos favoritos" : "Adicionar aos favoritos") {
            browser.favorites.contains(url) ? browser.removeFavorite(url) : browser.addFavorite(url)
        }
        Button("Adicionar à biblioteca") { state.load(urls: [url]) }
    }
}
