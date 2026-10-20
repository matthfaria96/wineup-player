import SwiftUI

struct PlaylistPanel: View {
    @ObservedObject var state: PlayerState

    var body: some View {
        Panel(title: state.listTitle) {
            VStack(spacing: 0) {
                ScrollViewReader { proxy in
                    ScrollView {
                        if state.listStyle == .grid {
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 8)], spacing: 8) {
                                ForEach(state.visibleTracks) { track in
                                    TrackTile(track: track, isCurrent: track.id == state.currentID)
                                        .id(track.id)
                                        .onTapGesture(count: 2) { state.play(track) }
                                        .contextMenu { TrackMenu(state: state, track: track) }
                                }
                            }
                            .padding(8)
                        } else {
                            LazyVStack(spacing: 0) {
                                ForEach(Array(state.visibleTracks.enumerated()), id: \.element.id) { offset, track in
                                    TrackRow(
                                        track: track,
                                        index: offset + 1,
                                        isCurrent: track.id == state.currentID,
                                        isSelected: track.id == state.selectedID,
                                        detailed: state.listStyle == .detailed
                                    )
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
                footer
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 6) {
            ChromeButton("Del") { state.deleteSelected() }.frame(width: 38)
            ChromeButton("Random") { state.playRandom() }.frame(width: 66)
            ColorDots(selection: $state.markFilter)
            Spacer(minLength: 0)
            ItemsCount(count: state.tracks.count)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }
}
