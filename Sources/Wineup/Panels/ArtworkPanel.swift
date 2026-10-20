import WineupCore
import SwiftUI

/// Capa em tela cheia com os dados da faixa sobrepostos; sem capa, mostra o símbolo de nota.
struct ArtworkPanel: View {
    @ObservedObject var state: PlayerState

    @Environment(\.theme) private var theme

    var body: some View {
        Panel(title: "") {
            ZStack(alignment: .bottomLeading) {
                LinearGradient(
                    colors: [theme.artworkTint.opacity(0.9), theme.artworkTint.opacity(0.35)],
                    startPoint: .top, endPoint: .bottom
                )
                if let cover = state.cover {
                    Image(nsImage: cover)
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .clipped()
                        .overlay(LinearGradient(colors: [.clear, .black.opacity(0.65)], startPoint: .center, endPoint: .bottom))
                } else {
                    Image(systemName: "music.note")
                        .font(.system(size: 120, weight: .regular))
                        .foregroundStyle(Color.black.opacity(0.28))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                info
                    .padding(16)
            }
        }
    }

    private var info: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let track = state.currentTrack {
                Text(track.artist).font(.system(size: 17, weight: .bold))
                Text(track.title).font(.system(size: 15, weight: .semibold))
                Text(track.album ?? "Álbum desconhecido").font(.system(size: 15, weight: .semibold))
                if let year = track.year { Text(year).font(.system(size: 15, weight: .bold)) }
                if let url = track.url {
                    Text(url.pathExtension.uppercased()).font(.system(size: 12, weight: .semibold))
                }
            }
        }
        .foregroundStyle(Color.white)
        .shadow(color: .black.opacity(0.6), radius: 3)
        .lineLimit(2)
    }
}
