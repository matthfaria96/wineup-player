import SwiftUI
import WineupCore

/// Playlist com a navegação da biblioteca embutida: grupos (álbuns, bandas...) ↔ faixas.
struct PlaylistPanel: View {
    @ObservedObject var state: PlayerState
    @ObservedObject var browser: LibraryBrowser
    @Environment(\.theme) private var theme

    var body: some View {
        Panel(title: browser.showingGroups ? browser.mode.title : state.listTitle) {
            VStack(spacing: 6) {
                topBar
                Group {
                    if !state.query.isEmpty {
                        trackList(state.searchResults)
                    } else if browser.showingGroups {
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

    private var topBar: some View {
        HStack(spacing: 6) {
            if browser.showingGroups {
                Picker("", selection: $browser.mode) {
                    ForEach(BrowseMode.allCases) { mode in
                        Image(systemName: mode.symbol).help(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(minWidth: 120, maxWidth: 170)
            } else {
                ChromeButton(action: { browser.showingGroups = true }) {
                    Label(browser.mode.title, systemImage: "chevron.left").labelStyle(.titleAndIcon)
                }
                .fixedSize()
            }
            searchField
        }
        .padding(.horizontal, 10)
    }

    private var searchField: some View {
        HStack(spacing: 5) {
            Image(systemName: "magnifyingglass").foregroundStyle(theme.mutedText)
            TextField("Buscar", text: $state.query).textFieldStyle(.plain).foregroundStyle(theme.text)
            if !state.query.isEmpty {
                Image(systemName: "xmark.circle.fill").foregroundStyle(theme.mutedText)
                    .onTapGesture { state.query = "" }
            }
        }
        .font(.system(size: 12))
        .frame(minWidth: 60)
        .padding(.horizontal, 7)
        .frame(height: 22)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.06)))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(theme.panelBorder, lineWidth: 1))
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
