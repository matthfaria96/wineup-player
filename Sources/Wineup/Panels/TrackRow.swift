import AppKit
import WineupCore
import SwiftUI

/// Linha de faixa usada na playlist e na busca.
struct TrackRow: View {
    private var rowBackground: Color {
        if isCurrent { return theme.currentRow.opacity(0.16) }
        if isSelected { return theme.rowSelection }
        return index % 2 == 0 ? Color.white.opacity(0.025) : Color.clear
    }

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
                Text("\(index)")
                    .font(.system(size: 11)).monospacedDigit()
                    .foregroundStyle(isCurrent ? theme.currentRow : theme.mutedText)
                    .frame(width: 28, alignment: .trailing)
                Text(track.displayName)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            Spacer(minLength: 4)
            if showsDuration {
                if let mark = track.mark {
                    Circle().fill(mark.color).frame(width: 7, height: 7)
                }
                Text(Clock.format(track.duration))
                    .font(.system(size: 12))
                    .monospacedDigit()
                    .foregroundStyle(isCurrent ? theme.currentRow : theme.mutedText)
                    .frame(width: 44, alignment: .trailing)
            }
        }
        .font(.system(size: 13))
        .foregroundStyle(isCurrent ? theme.currentRow : theme.text)
        .padding(.horizontal, 14)
        .frame(height: detailed ? 40 : 29)
        .background(rowBackground)
        .overlay(alignment: .leading) {
            if isCurrent { Rectangle().fill(theme.currentRow).frame(width: 3) }
        }
        .padding(.horizontal, 6)
        .contentShape(Rectangle())
    }
}

/// Bloco da lista em grade.
struct TrackTile: View {
    let track: Track
    let isCurrent: Bool
    @StateObject private var covers = CoverLoader()
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ZStack(alignment: .topTrailing) {
                RoundedRectangle(cornerRadius: 6).fill(theme.artworkTint)
                    .aspectRatio(1, contentMode: .fit)
                    .overlay {
                        if let image = covers.image {
                            Image(nsImage: image).resizable().scaledToFill()
                        } else {
                            Image(systemName: "music.note").font(.system(size: 30)).foregroundStyle(.black.opacity(0.3))
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                if let mark = track.mark { Circle().fill(mark.color).frame(width: 10, height: 10).padding(6) }
            }
            Text(track.title).font(.system(size: 12, weight: .semibold)).lineLimit(1)
            Text(track.artist).font(.system(size: 10)).foregroundStyle(theme.mutedText).lineLimit(1)
        }
        .foregroundStyle(isCurrent ? theme.currentRow : theme.text)
        .onAppear { covers.load(track.url) }
    }
}

/// Carrega a capa embutida de uma faixa fora da main thread, com cache em memória.
final class CoverLoader: ObservableObject {
    @Published var image: NSImage?
    private static let cache = NSCache<NSURL, NSImage>()

    func load(_ url: URL?) {
        guard image == nil, let url else { return }
        if let cached = Self.cache.object(forKey: url as NSURL) { image = cached; return }
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let found = TrackLoader.cover(for: url) else { return }
            Self.cache.setObject(found, forKey: url as NSURL)
            DispatchQueue.main.async { self?.image = found }
        }
    }
}

/// Menu de contexto da faixa: tag de cor e playlists.
struct TrackMenu: View {
    let state: PlayerState
    let track: Track

    var body: some View {
        Button("Tocar") { state.play(track) }
        Button("Remover da lista") { state.selectedID = track.id; state.deleteSelected() }
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
