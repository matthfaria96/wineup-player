import WineupCore
import SwiftUI

/// Capa sempre quadrada (1:1), do tamanho da largura do painel; os dados da faixa ficam
/// embaixo e ocupam o resto do espaço. Sem capa, mostra o símbolo de nota no mesmo quadrado.
struct ArtworkPanel: View {
    @ObservedObject var state: PlayerState

    @Environment(\.theme) private var theme

    var body: some View {
        Panel(title: "Capa") {
            VStack(alignment: .leading, spacing: 12) {
                cover
                    .aspectRatio(1, contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .layoutPriority(1)
                info
                Spacer(minLength: 0)
            }
            .padding(12)
        }
    }

    private var cover: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6)
                .fill(LinearGradient(colors: [theme.artworkTint.opacity(0.9), theme.artworkTint.opacity(0.35)],
                                     startPoint: .top, endPoint: .bottom))
            if let image = state.cover {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "music.note")
                    .font(.system(size: 90, weight: .regular))
                    .foregroundStyle(Color.black.opacity(0.28))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private var info: some View {
        VStack(alignment: .leading, spacing: 3) {
            if let track = state.currentTrack {
                Text(track.title).font(.system(size: 15, weight: .bold)).foregroundStyle(theme.text)
                Text(track.artist).font(.system(size: 13, weight: .medium)).foregroundStyle(theme.text)
                Text([track.album ?? "Álbum desconhecido", track.year].compactMap { $0 }.joined(separator: " · "))
                    .font(.system(size: 12)).foregroundStyle(theme.mutedText)
                if let url = track.url {
                    Text(url.pathExtension.uppercased()).font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(theme.mutedText)
                }
            } else {
                Text("Nada tocando").font(.system(size: 13)).foregroundStyle(theme.mutedText)
            }
        }
        .lineLimit(1)
    }
}
