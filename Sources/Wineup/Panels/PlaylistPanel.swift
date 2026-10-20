import SwiftUI

struct PlaylistPanel: View {
    @ObservedObject var state: PlayerState

    var body: some View {
        Panel(title: "Playlist") {
            VStack(spacing: 0) {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(state.visibleTracks) { track in
                                TrackRow(
                                    track: track,
                                    isCurrent: track.id == state.currentID,
                                    isSelected: track.id == state.selectedID
                                )
                                .id(track.id)
                                .onTapGesture(count: 2) { state.play(track) }
                                .onTapGesture { state.selectedID = track.id }
                            }
                        }
                    }
                    .onAppear { proxy.scrollTo(state.currentID, anchor: .center) }
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
