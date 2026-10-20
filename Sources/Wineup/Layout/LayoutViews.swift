import SwiftUI

/// Padrão: playlist alta à esquerda; player, equalizador e capa à direita.
struct StandardLayout: View {
    @ObservedObject var state: PlayerState

    var body: some View {
        HStack(spacing: 8) {
            PlaylistPanel(state: state, browser: state.browser)
            VStack(spacing: 8) {
                PlayerPanel(state: state).frame(height: 262)
                EqualizerPanel(state: state).frame(height: 190)
                ArtworkPanel(state: state)
            }
            .frame(width: 380)
        }
    }
}

/// Compacto: uma coluna, como o player clássico (player, equalizador, playlist).
struct CompactLayout: View {
    @ObservedObject var state: PlayerState

    var body: some View {
        VStack(spacing: 8) {
            PlayerPanel(state: state).frame(height: 262)
            EqualizerPanel(state: state).frame(height: 190)
            PlaylistPanel(state: state, browser: state.browser)
        }
        .frame(maxWidth: 520)
        .frame(maxWidth: .infinity)
    }
}

/// Completo: todos os painéis, inclusive letras.
struct FullLayout: View {
    @ObservedObject var state: PlayerState

    var body: some View {
        HStack(spacing: 8) {
            PlaylistPanel(state: state, browser: state.browser)
            VStack(spacing: 8) {
                PlayerPanel(state: state).frame(height: 262)
                EqualizerPanel(state: state).frame(height: 190)
                LyricsPanel(state: state)
            }
            .frame(width: 380)
            ArtworkPanel(state: state).frame(width: 320)
        }
    }
}
