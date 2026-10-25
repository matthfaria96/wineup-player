import AppKit
import SwiftUI
import WineupCore

/// Lista de grupos do visualizador (álbuns, artistas, gêneros, playlists) da pasta atual.
struct LibraryGroupsView: View {
    @ObservedObject var state: PlayerState
    @ObservedObject var browser: LibraryBrowser
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(spacing: 6) {
            if browser.view == .playlists { playlistBar.padding(.horizontal, 14) }
            ScrollView {
                if browser.groups.isEmpty && !browser.isLoading {
                    Text(emptyText)
                        .font(.system(size: 12)).foregroundStyle(theme.mutedText)
                        .multilineTextAlignment(.center).padding(.top, 30)
                }
                // Estilo Grade: álbuns, artistas e estilos viram capas lado a lado.
                if state.listStyle == .grid {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 10)], spacing: 12) {
                        ForEach(browser.groups, id: \.id) { group in
                            GroupTile(group: group, symbol: browser.view.symbol)
                                .contentShape(Rectangle())
                                .onTapGesture { browser.open(group) }
                                .contextMenu { menu(group) }
                        }
                    }
                    .padding(10)
                } else {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(browser.groups.enumerated()), id: \.element.id) { index, group in
                            GroupRow(group: group, index: index, symbol: browser.view.symbol)
                                .contentShape(Rectangle())
                                .onTapGesture { browser.open(group) }
                                .contextMenu { menu(group) }
                        }
                    }
                }
            }
        }
    }

    private var emptyText: String {
        browser.view == .playlists
            ? String(localized: "Nenhuma playlist ainda.\nCrie uma com + Nova ou marque faixas com uma cor.")
            : String(localized: "Nenhuma música nesta pasta.\nEscolha outra pasta no seletor acima.")
    }

    private var playlistBar: some View {
        HStack {
            Toggle("Mostrar playlists de tags", isOn: $browser.showColorTags)
                .toggleStyle(.checkbox)
                .font(.system(size: 11))
                .foregroundStyle(theme.text)
            Spacer()
            ChromeButton("+ Nova") { state.newPlaylist(with: nil) }.frame(width: 64)
        }
    }

    @ViewBuilder private func menu(_ group: ViewGroup) -> some View {
        Button("Abrir") { browser.open(group) }
        Button("Tocar") { state.playGroup(group) }
        if let id = group.playlistID {
            Divider()
            Button("Renomear…") {
                if let name = TextPrompt.ask(title: "Renomear playlist", value: group.title) {
                    browser.renamePlaylist(id: id, to: name)
                }
            }
            Button("Apagar playlist", role: .destructive) { browser.deletePlaylist(id: id) }
        }
    }
}

/// Linha de grupo com capinha (álbuns/artistas/gêneros), cor (tags) ou ícone (playlists).
private struct GroupRow: View {
    let group: ViewGroup
    let index: Int
    let symbol: String
    @Environment(\.theme) private var theme
    @StateObject private var covers = CoverLoader()

    var body: some View {
        HStack(spacing: 10) {
            artwork
            VStack(alignment: .leading, spacing: 1) {
                Text(group.title).font(.system(size: 13, weight: .medium)).lineLimit(1)
                if !group.subtitle.isEmpty {
                    Text(group.subtitle).font(.system(size: 11)).foregroundStyle(theme.mutedText).lineLimit(1)
                }
            }
            Spacer(minLength: 4)
            Text("\(group.count)").font(.system(size: 11)).monospacedDigit().foregroundStyle(theme.mutedText)
            Image(systemName: "chevron.right").font(.system(size: 9)).foregroundStyle(theme.mutedText)
        }
        .foregroundStyle(theme.text)
        .padding(.horizontal, 14)
        .frame(height: 44)
        .background(index % 2 == 0 ? Color.white.opacity(0.025) : Color.clear)
        .padding(.horizontal, 6)
        .onAppear { covers.load(group.coverURL) }
    }

    @ViewBuilder private var artwork: some View {
        if let color = group.color {
            Circle().fill(color.color).frame(width: 14, height: 14).frame(width: 34)
        } else if let image = covers.image {
            Image(nsImage: image).resizable().scaledToFill()
                .frame(width: 34, height: 34).clipShape(RoundedRectangle(cornerRadius: 4))
        } else {
            Image(systemName: group.playlistID != nil ? "music.note.list" : symbol)
                .frame(width: 34, height: 34)
                .background(RoundedRectangle(cornerRadius: 4).fill(theme.artworkTint))
                .foregroundStyle(theme.mutedText)
        }
    }
}

/// Capa do grupo na Grade (álbum, artista ou estilo), com nome e contagem embaixo.
private struct GroupTile: View {
    let group: ViewGroup
    let symbol: String
    @Environment(\.theme) private var theme
    @StateObject private var covers = CoverLoader()

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            RoundedRectangle(cornerRadius: 6).fill(theme.artworkTint)
                .aspectRatio(1, contentMode: .fit)
                .overlay { artwork }
                .clipShape(RoundedRectangle(cornerRadius: 6))
            Text(group.title).font(.system(size: 12, weight: .semibold)).lineLimit(1)
            Text(group.subtitle.isEmpty ? "\(group.count)" : group.subtitle)
                .font(.system(size: 10)).foregroundStyle(theme.mutedText).lineLimit(1)
        }
        .foregroundStyle(theme.text)
        .onAppear { covers.load(group.coverURL) }
        .onDisappear { covers.cancel() }
    }

    @ViewBuilder private var artwork: some View {
        if let color = group.color {
            Circle().fill(color.color).frame(width: 34, height: 34)
        } else if let image = covers.image {
            Image(nsImage: image).resizable().scaledToFill()
        } else {
            Image(systemName: group.playlistID != nil ? "music.note.list" : symbol)
                .font(.system(size: 30)).foregroundStyle(theme.mutedText)
        }
    }
}

/// Caixa de texto simples (AppKit), sem depender de @State.
enum TextPrompt {
    static func ask(title: String.LocalizationValue, value: String) -> String? {
        let alert = NSAlert()
        alert.messageText = String(localized: title)
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        field.stringValue = value
        alert.accessoryView = field
        alert.addButton(withTitle: String(localized: "OK"))
        alert.addButton(withTitle: String(localized: "Cancelar"))
        return alert.runModal() == .alertFirstButtonReturn ? field.stringValue : nil
    }
}
