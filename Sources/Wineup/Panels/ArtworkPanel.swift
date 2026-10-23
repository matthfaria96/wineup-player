import WineupCore
import AppKit
import SwiftUI

/// Capa sempre quadrada (1:1), do tamanho da largura do painel; os dados da faixa ficam
/// embaixo e ocupam o resto do espaço. Sem capa, mostra o símbolo de nota no mesmo quadrado.
struct ArtworkPanel: View {
    @ObservedObject var state: PlayerState
    @AppStorage(VisualMode.key) private var modeRaw = VisualMode.cover.rawValue
    @AppStorage(VideoCategoryStore.selectedKey) private var videoCategory = ""
    @ObservedObject private var videoStore = VideoCategoryStore.shared
    @State private var showVideoSettings = false

    @Environment(\.theme) private var theme

    private var mode: VisualMode { VisualMode(rawValue: modeRaw) ?? .cover }

    var body: some View {
        Panel(title: mode == .cover ? "Capa" : "Visual") {
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
            switch mode {
            case .cover: artwork
            case .videos: videos
            default:
                VisualScene(mode: mode, energy: { [weak state] in
                    MainActor.assumeIsolated {
                        let levels = state?.meterModel.levels ?? []
                        return min(1, (levels.reduce(0, +) / Double(max(levels.count, 1))) * 1.4)
                    }
                }, seed: state.currentTrack?.id.seed ?? 0)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(alignment: .topTrailing) { modeMenu }
    }

    /// Menu no canto da capa: capa, cenas animadas e o submenu de vídeos por categoria.
    private var modeMenu: some View {
        Menu {
            ForEach(VisualMode.allCases.filter { $0 != .videos }) { m in
                Button { modeRaw = m.rawValue } label: {
                    Label(m.title, systemImage: mode == m ? "checkmark" : m.symbol)
                }
            }
            Menu {
                ForEach(videoStore.enabled) { c in
                    Button {
                        videoCategory = c.id
                        modeRaw = VisualMode.videos.rawValue
                    } label: {
                        Label(c.name, systemImage: mode == .videos && videoCategory == c.id ? "checkmark" : c.symbol)
                    }
                }
                if videoStore.enabled.isEmpty { Text("Nenhuma categoria ligada") }
                Divider()
                Button { showVideoSettings = true } label: { Label("Configurar categorias…", systemImage: "gearshape") }
            } label: {
                Label("Vídeos", systemImage: "film")
            }
        } label: {
            Image(systemName: mode.symbol)
                .font(.system(size: 11, weight: .semibold))
        }
        .skinMenuChrome(compact: true)
        .padding(8)
        .help("Capa, cena animada ou vídeos por categoria")
        .accessibilityLabel("Escolher o que aparece no lugar da capa")
        .sheet(isPresented: $showVideoSettings) { VideoCategoriesView() }
    }

    @ViewBuilder private var videos: some View {
        let category = videoStore.category(videoCategory) ?? videoStore.enabled.first
        let clips = category?.clips ?? []
        if clips.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "film").font(.system(size: 40)).foregroundStyle(theme.mutedText)
                Text(category == nil ? "Nenhuma categoria de vídeo ligada." : "A categoria “\(category!.name)” está sem clipes. Acople uma pasta com vídeos em Configurar categorias.")
                    .font(.system(size: 12)).foregroundStyle(theme.mutedText).multilineTextAlignment(.center)
                Button("Configurar categorias…") { showVideoSettings = true }.controlSize(.small)
            }
            .padding(20)
        } else {
            VideoWall(clips: clips, trackKey: state.currentTrack?.id.seed ?? 0)
                .overlay(alignment: .bottomLeading) {
                    Text(category?.name ?? "").font(.system(size: 10, weight: .semibold)).foregroundStyle(.white.opacity(0.85))
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(Capsule().fill(Color.black.opacity(0.4))).padding(8)
                }
        }
    }

    @ViewBuilder private var artwork: some View {
        ZStack {
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
