import AppKit
import SwiftUI
import WineupCore

/// Biblioteca: visão por Álbuns, Bandas, Pastas, Estilos ou Playlists, mais a busca.
struct LibraryPanel: View {
    @ObservedObject var state: PlayerState
    @ObservedObject var browser: LibraryBrowser
    @Environment(\.theme) private var theme

    var body: some View {
        Panel(title: "Biblioteca") {
            VStack(spacing: 6) {
                Picker("", selection: $browser.mode) {
                    ForEach(BrowseMode.allCases) { mode in
                        Label(mode.title, systemImage: mode.symbol).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                field
                if !state.query.isEmpty {
                    results
                } else {
                    if browser.mode == .playlists { playlistBar }
                    groupList
                }
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 8)
        }
        .onAppear { browser.reload() }
    }

    private var field: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").foregroundStyle(theme.mutedText)
            TextField("Buscar", text: $state.query).textFieldStyle(.plain).foregroundStyle(theme.text)
            if !state.query.isEmpty {
                Image(systemName: "xmark.circle.fill").foregroundStyle(theme.mutedText)
                    .onTapGesture { state.query = "" }
            }
        }
        .font(.system(size: 13))
        .padding(.horizontal, 8)
        .frame(height: 26)
        .background(RoundedRectangle(cornerRadius: 7).fill(Color.white.opacity(0.06)))
        .overlay(RoundedRectangle(cornerRadius: 7).stroke(theme.panelBorder, lineWidth: 1))
    }

    private var playlistBar: some View {
        HStack {
            Toggle("Playlists de tags", isOn: $browser.showColorTags)
                .toggleStyle(.checkbox)
                .font(.system(size: 11))
                .foregroundStyle(theme.text)
            Spacer()
            ChromeButton("+ Nova") { state.newPlaylist(with: nil) }.frame(width: 64)
        }
    }

    private var groupList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if browser.groups.isEmpty {
                    Text(browser.isLoading ? "Carregando…" : emptyText)
                        .font(.system(size: 12)).foregroundStyle(theme.mutedText).padding(.top, 20)
                }
                ForEach(browser.groups) { group in
                    row(group)
                        .contentShape(Rectangle())
                        .onTapGesture { browser.open(group) }
                        .contextMenu { groupMenu(group) }
                }
            }
        }
    }

    private var emptyText: String {
        browser.mode == .playlists ? "Crie uma playlist ou marque faixas com uma cor" : "Nada na biblioteca ainda"
    }

    private func row(_ group: BrowseGroup) -> some View {
        HStack(spacing: 8) {
            icon(group)
            VStack(alignment: .leading, spacing: 1) {
                Text(group.title).font(.system(size: 13, weight: .medium)).lineLimit(1)
                if !group.subtitle.isEmpty {
                    Text(group.subtitle).font(.system(size: 10)).foregroundStyle(theme.mutedText).lineLimit(1)
                }
            }
            Spacer(minLength: 4)
            Text("\(group.count)").font(.system(size: 11)).monospacedDigit().foregroundStyle(theme.mutedText)
        }
        .foregroundStyle(theme.text)
        .padding(.horizontal, 6)
        .frame(height: group.subtitle.isEmpty ? 26 : 36)
        .background(browser.selected == group.kind ? theme.rowSelection : Color.clear)
    }

    @ViewBuilder private func icon(_ group: BrowseGroup) -> some View {
        switch group.kind {
        case .colorTag(let color):
            Circle().fill(color.color).frame(width: 12, height: 12)
        case .singles:
            Image(systemName: "music.note").frame(width: 14).foregroundStyle(theme.accent)
        default:
            Image(systemName: browser.mode.symbol).frame(width: 14).foregroundStyle(theme.mutedText)
        }
    }

    @ViewBuilder private func groupMenu(_ group: BrowseGroup) -> some View {
        if case .playlist(let id) = group.kind {
            Button("Renomear…") {
                if let name = TextPrompt.ask(title: "Renomear playlist", value: group.title) {
                    browser.renamePlaylist(id: id, to: name)
                }
            }
            Button("Apagar playlist", role: .destructive) { browser.deletePlaylist(id: id) }
        } else {
            Button("Abrir") { browser.open(group) }
        }
    }

    private var results: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(Array(state.searchResults.enumerated()), id: \.element.id) { offset, track in
                    TrackRow(track: track, index: offset + 1, isCurrent: track.id == state.currentID,
                             isSelected: track.id == state.selectedID, showsDuration: false)
                        .onTapGesture(count: 2) { state.play(track) }
                        .onTapGesture { state.selectedID = track.id }
                }
            }
        }
    }
}

/// Caixa de texto simples (AppKit), sem depender de @State.
enum TextPrompt {
    static func ask(title: String, value: String) -> String? {
        let alert = NSAlert()
        alert.messageText = title
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        field.stringValue = value
        alert.accessoryView = field
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancelar")
        return alert.runModal() == .alertFirstButtonReturn ? field.stringValue : nil
    }
}
