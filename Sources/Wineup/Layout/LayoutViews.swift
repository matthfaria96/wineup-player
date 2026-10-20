import SwiftUI

/// Os três arranjos de painéis, copiados da disposição dos prints de referência.
struct GridLayout: View {
    @ObservedObject var state: PlayerState

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                PlayerPanel(state: state)
                EqualizerPanel(state: state)
                SearchPanel(state: state)
            }
            .frame(height: 262)
            HStack(spacing: 8) {
                PlaylistPanel(state: state)
                LyricsPanel(state: state)
                ArtworkPanel(state: state)
            }
        }
    }
}

struct CompactLayout: View {
    @ObservedObject var state: PlayerState

    var body: some View {
        HStack(spacing: 8) {
            PlaylistPanel(state: state)
            VStack(spacing: 8) {
                PlayerPanel(state: state).frame(height: 262)
                EqualizerPanel(state: state).frame(height: 170)
                ArtworkPanel(state: state)
            }
            .frame(width: 350)
        }
    }
}

struct StudioLayout: View {
    @ObservedObject var state: PlayerState

    var body: some View {
        HStack(spacing: 8) {
            VStack(spacing: 8) {
                PlayerPanel(state: state).frame(height: 262)
                EqualizerPanel(state: state).frame(height: 170)
                PlaylistPanel(state: state)
            }
            .frame(width: 350)
            VStack(spacing: 8) {
                ArtworkPanel(state: state)
                LyricsPanel(state: state)
            }
            SearchPanel(state: state)
                .frame(width: 300)
        }
    }
}
