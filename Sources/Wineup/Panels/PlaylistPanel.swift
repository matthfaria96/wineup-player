import SwiftUI
import WineupCore

/// Playlist com a navegação da biblioteca embutida: grupos (álbuns, bandas...) ↔ faixas.
struct PlaylistPanel: View {
    @ObservedObject var state: PlayerState
    @ObservedObject var browser: LibraryBrowser
    @Environment(\.theme) private var theme
    @Environment(\.openWindow) private var openWindow
    /// Página do artista: lançamento escolhido (nil = todas as músicas).
    @State private var artistRelease: String?

    private var isArtistPage: Bool { browser.view == .artists && browser.group != nil && state.query.isEmpty }

    private var artistHeader: ArtistHeader {
        ArtistHeader(state: state, artist: browser.group?.title ?? "", tracks: state.visibleTracks, release: $artistRelease)
    }

    var body: some View {
        Panel(title: "") {
            VStack(spacing: 0) {
                NavBar(state: state, browser: browser)
                Divider().opacity(0.5)
                titleBlock
                if isArtistPage {
                    backRow
                    artistHeader
                } else if browser.group != nil && state.query.isEmpty { groupHeader }
                if showsColumns { columnHeader }
                Group {
                    if !state.query.isEmpty {
                        trackList(state.searchResults)
                    } else if browser.showsGroups {
                        LibraryGroupsView(state: state, browser: browser)
                    } else if isArtistPage {
                        trackList(artistHeader.listed())
                    } else {
                        trackList(state.visibleTracks)
                    }
                }
                .frame(maxHeight: .infinity)
                .onChange(of: browser.group?.id) { _, _ in artistRelease = nil }
                footer
            }
        }
    }

    private var showsColumns: Bool {
        (!browser.showsGroups || !state.query.isEmpty) && state.listStyle != .grid
    }

    // MARK: Visualizador (título = como ver a pasta)

    private var titleBlock: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 3) {
                Menu {
                    ForEach(ViewMode.allCases) { mode in
                        Button { browser.setView(mode) } label: { Label(mode.title, systemImage: mode.symbol) }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text(state.query.isEmpty ? browser.view.title : "Busca")
                            .font(.system(size: 24, weight: .bold)).lineLimit(1)
                        Image(systemName: "chevron.down").font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(theme.mutedText)
                    }
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("Ver esta pasta por: Pastas, Músicas, Álbuns, Artistas, Gêneros ou Playlists")
                Text(subtitle)
                    .font(.system(size: 12)).foregroundStyle(theme.mutedText).lineLimit(1)
            }
            Spacer(minLength: 8)
            if browser.isLoading { ProgressView().controlSize(.small) }
            Text(countText).font(.system(size: 12)).foregroundStyle(theme.mutedText)
        }
        .foregroundStyle(theme.text)
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 10)
    }

    private var subtitle: String {
        if !state.query.isEmpty { return "Resultados para \u{201C}\(state.query)\u{201D}" }
        if browser.view == .playlists { return "Suas playlists e tags de cor" }
        if browser.view == .queue { return "Próximas músicas · arraste para reordenar" }
        return "Em " + NavPlaces.displayPath(browser.folder)
    }

    private var countText: String {
        if browser.showsGroups && state.query.isEmpty {
            let n = browser.groups.count
            let noun: String
            switch browser.view {
            case .albums: noun = n == 1 ? "álbum" : "álbuns"
            case .artists: noun = n == 1 ? "artista" : "artistas"
            case .genres: noun = n == 1 ? "gênero" : "gêneros"
            default: noun = n == 1 ? "playlist" : "playlists"
            }
            return "\(n) \(noun)"
        }
        let n = state.query.isEmpty ? state.visibleTracks.count : state.searchResults.count
        return n == 1 ? "1 faixa" : "\(n) faixas"
    }

    /// Linha do grupo aberto (álbum, artista, gênero, playlist): voltar + nome.
    private var groupHeader: some View {
        HStack(spacing: 8) {
            Button { browser.closeGroup() } label: {
                Label(browser.view.title, systemImage: "chevron.left").labelStyle(.titleAndIcon)
            }
            .buttonStyle(.borderless)
            .foregroundStyle(theme.mutedText)
            Text(browser.group?.title ?? "").font(.system(size: 15, weight: .semibold)).lineLimit(1)
            Spacer()
            if let group = browser.group, let first = state.visibleTracks.first {
                ChromeButton(action: { state.play(first, from: state.visibleTracks) }) {
                    Label("Tocar", systemImage: "play.fill").labelStyle(.titleAndIcon)
                }
                .fixedSize()
                .help("Tocar \(group.title)")
            }
        }
        .foregroundStyle(theme.text)
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    /// Voltar para a lista de artistas (na página do artista).
    private var backRow: some View {
        HStack {
            Button { browser.closeGroup() } label: {
                Label(browser.view.title, systemImage: "chevron.left").labelStyle(.titleAndIcon)
            }
            .buttonStyle(.borderless)
            .foregroundStyle(theme.mutedText)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 4)
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
            Text("Troque a pasta no seletor acima, abra uma pasta (⌘O) ou arraste músicas para a janela.")
                .font(.system(size: 11)).foregroundStyle(theme.mutedText)
                .multilineTextAlignment(.center).frame(maxWidth: 280)
        }
        .foregroundStyle(theme.text)
        .padding(.top, 40)
    }

    /// Na visão Pastas: subpastas antes das músicas (clique entra na pasta).
    @ViewBuilder private var folderRows: some View {
        if browser.view == .files, state.query.isEmpty {
            ForEach(browser.subfolders, id: \.self) { url in
                HStack(spacing: 8) {
                    Image(systemName: "folder.fill").foregroundStyle(theme.accent.opacity(0.8)).frame(width: 28)
                    Text(url.lastPathComponent).lineLimit(1)
                    Spacer()
                    Image(systemName: "chevron.right").font(.system(size: 9)).foregroundStyle(theme.mutedText)
                }
                .font(.system(size: 13))
                .foregroundStyle(theme.text)
                .padding(.horizontal, 14)
                .frame(height: 29)
                .contentShape(Rectangle())
                .onTapGesture { browser.go(folder: url) }
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
                                .onTapGesture(count: 2) { state.playFromList(track, list: tracks) }
                                .contextMenu { TrackMenu(state: state, track: track) }
                        }
                    }
                    .padding(8)
                } else {
                    LazyVStack(spacing: 0) {
                        folderRows
                        if tracks.isEmpty && (browser.view != .files || browser.subfolders.isEmpty) && !browser.isLoading {
                            emptyState
                        }
                        ForEach(tracks.indices, id: \.self) { offset in
                            let track = tracks[offset]
                            SelectableTrackRow(selection: state.selection, track: track, index: offset + 1,
                                               isCurrent: track.id == state.currentID,
                                               detailed: state.listStyle == .detailed)
                                .id(track.id)
                                .onTapGesture(count: 2) { state.playFromList(track, list: tracks) }
                                .simultaneousGesture(TapGesture().onEnded { state.selectedID = track.id })
                                .contextMenu { TrackMenu(state: state, track: track) }
                                .modifier(QueueReorder(enabled: browser.view == .queue, index: offset, state: state))
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
            if let message = state.statusMessage {
                Text(message)
                    .font(.system(size: 11))
                    .foregroundStyle(theme.mutedText)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
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
                Divider()
                Button("Editar, criar, importar ou exportar skins…") { openWindow(id: "themes") }
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
        Button("Abrir") { browser.go(folder: url) }
        Button("Tocar tudo") { state.playFolder(url) }
        Divider()
        Button("Copiar caminho") { PathActions.copy(url) }
        Button("Mostrar no Finder") { PathActions.reveal(url) }
        Divider()
        Button(browser.favorites.contains(url) ? "Remover dos favoritos" : "Adicionar aos favoritos") {
            browser.favorites.contains(url) ? browser.removeFavorite(url) : browser.addFavorite(url)
        }
        Button("Adicionar à biblioteca") { state.load(urls: [url]) }
        Button("Usar como pasta padrão") { state.makeDefaultFolder(url) }
    }
}

/// Na visão Fila: arrastar uma linha e soltar sobre outra muda a ordem.
private struct QueueReorder: ViewModifier {
    let enabled: Bool
    let index: Int
    let state: PlayerState

    func body(content: Content) -> some View {
        if enabled {
            content
                .onDrag { NSItemProvider(object: "\(index)" as NSString) }
                .onDrop(of: [.text], isTargeted: nil) { providers in
                    guard let provider = providers.first else { return false }
                    _ = provider.loadObject(ofClass: NSString.self) { object, _ in
                        guard let text = object as? String, let source = Int(text) else { return }
                        DispatchQueue.main.async { state.moveInQueue(from: source, to: index) }
                    }
                    return true
                }
        } else {
            content
        }
    }
}
