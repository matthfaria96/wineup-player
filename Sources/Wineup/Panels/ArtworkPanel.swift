import WineupCore
import AppKit
import SwiftUI

/// Capa sempre quadrada (1:1), do tamanho da largura do painel; os dados da faixa ficam
/// embaixo e ocupam o resto do espaço. Sem capa, mostra o símbolo de nota no mesmo quadrado.
struct ArtworkPanel: View {
    @ObservedObject var state: PlayerState
    @AppStorage(VisualMode.key) private var modeRaw = VisualMode.cover.rawValue
    @AppStorage(VisualMode.videoFolderKey) private var videoFolder = ""

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

    /// Menu no canto da capa: capa ou uma cena; para vídeos, a pasta.
    private var modeMenu: some View {
        Menu {
            Picker("Mostrar", selection: $modeRaw) {
                ForEach(VisualMode.allCases) { m in Label(m.title, systemImage: m.symbol).tag(m.rawValue) }
            }
            .pickerStyle(.inline)
            Divider()
            Button(videoFolder.isEmpty ? "Escolher a pasta de vídeos…" : "Trocar a pasta de vídeos…") { chooseVideoFolder() }
        } label: {
            Image(systemName: mode.symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white)
                .padding(6)
                .background(Circle().fill(Color.black.opacity(0.45)))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .padding(8)
        .help("Capa ou visual animado (aurora, fiorde, cidade, universo ou seus vídeos)")
        .accessibilityLabel("Escolher o que aparece no lugar da capa")
    }

    @ViewBuilder private var videos: some View {
        let folder = videoFolder.isEmpty ? nil : URL(fileURLWithPath: videoFolder)
        if VideoWall.videos(in: folder).isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "film").font(.system(size: 40)).foregroundStyle(theme.mutedText)
                Text("Escolha uma pasta com vídeos (MP4 ou MOV): seus clipes de anime, cenas de filmes, viagens…")
                    .font(.system(size: 12)).foregroundStyle(theme.mutedText).multilineTextAlignment(.center)
                Button("Escolher pasta…") { chooseVideoFolder() }.controlSize(.small)
            }
            .padding(20)
        } else {
            VideoWall(folder: folder, trackKey: state.currentTrack?.id.seed ?? 0)
        }
    }

    private func chooseVideoFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.message = "Escolha a pasta com os vídeos que vão passar no lugar da capa (sem som)"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        videoFolder = url.path
        modeRaw = VisualMode.videos.rawValue
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
