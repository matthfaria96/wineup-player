import WineupCore
import SwiftUI

/// Linha de faixa usada na playlist e na busca.
struct TrackRow: View {
    let track: Track
    let index: Int
    let isCurrent: Bool
    let isSelected: Bool
    var showsDuration = true
    var detailed = false

    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: 6) {
            if detailed {
                Image(systemName: "music.note")
                    .frame(width: 30, height: 30)
                    .background(RoundedRectangle(cornerRadius: 4).fill(theme.artworkTint))
                VStack(alignment: .leading, spacing: 1) {
                    Text(track.title).lineLimit(1)
                    Text([track.artist, track.album].compactMap { $0 }.joined(separator: " · "))
                        .font(.system(size: 11)).foregroundStyle(theme.mutedText).lineLimit(1)
                }
            } else {
                Text("\(index). \(track.displayName)")
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            Spacer(minLength: 4)
            if showsDuration {
                if let mark = track.mark {
                    Image(systemName: "heart.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(mark.color)
                }
                Text(Clock.format(track.duration))
                    .monospacedDigit()
                    .frame(width: 44, alignment: .trailing)
            }
        }
        .font(.system(size: 13))
        .foregroundStyle(isCurrent ? theme.currentRow : theme.text)
        .padding(.horizontal, 10)
        .frame(height: detailed ? 40 : 24)
        .background(isSelected ? theme.rowSelection : Color.clear)
        .contentShape(Rectangle())
    }
}

/// Bloco da lista em grade.
struct TrackTile: View {
    let track: Track
    let isCurrent: Bool
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ZStack(alignment: .topTrailing) {
                RoundedRectangle(cornerRadius: 6).fill(theme.artworkTint)
                    .aspectRatio(1, contentMode: .fit)
                    .overlay(Image(systemName: "music.note").font(.system(size: 30)).foregroundStyle(.black.opacity(0.3)))
                if let mark = track.mark { Circle().fill(mark.color).frame(width: 10, height: 10).padding(6) }
            }
            Text(track.title).font(.system(size: 12, weight: .semibold)).lineLimit(1)
            Text(track.artist).font(.system(size: 10)).foregroundStyle(theme.mutedText).lineLimit(1)
        }
        .foregroundStyle(isCurrent ? theme.currentRow : theme.text)
    }
}

/// Menu de contexto da faixa: tag de cor e playlists.
struct TrackMenu: View {
    let state: PlayerState
    let track: Track

    var body: some View {
        Button("Tocar") { state.play(track) }
        Menu("Tag de cor") {
            ForEach(MarkColor.allCases) { color in
                Button(color.displayName) { state.setMark(color, on: track) }
            }
            Divider()
            Button("Remover tag") { state.setMark(nil, on: track) }
        }
        Menu("Adicionar à playlist") {
            ForEach(state.browser.allPlaylists()) { list in
                Button(list.name) { state.addToPlaylist(track, playlistID: list.id) }
            }
            Divider()
            Button("Nova playlist com esta faixa") { state.newPlaylist(with: track) }
        }
    }
}
