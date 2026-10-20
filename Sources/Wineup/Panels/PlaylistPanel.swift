import SwiftUI
import WineupCore

/// Playlist com a navegação da biblioteca embutida: grupos (álbuns, bandas...) ↔ faixas.
struct PlaylistPanel: View {
    @ObservedObject var state: PlayerState
    @ObservedObject var browser: LibraryBrowser
    @Environment(\.theme) private var theme

    var body: some View {
        Panel(title: panelTitle) {
            VStack(spacing: 4) {
                NavBar(state: state, browser: browser)
                Divider().opacity(0.4)
                Group {
                    if !state.query.isEmpty {
                        trackList(state.searchResults)
                    } else if browser.location == .library && browser.showingGroups {
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

    private var panelTitle: String {
        if browser.location == .library && browser.showingGroups { return browser.mode.title }
        return state.listTitle
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
            Spacer(minLength: 0)
            ItemsCount(count: state.tracks.count)
                .layoutPriority(-1)
        }
        .padding(.horizontal, 10)
        .padding(.bottom, 8)
    }
}
