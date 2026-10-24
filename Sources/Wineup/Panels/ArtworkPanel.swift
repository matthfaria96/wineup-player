import WineupCore
import AppKit
import SwiftUI

/// Capa sempre quadrada (1:1), centrada no painel, com o formato do arquivo no canto.
/// Sem capa, mostra o símbolo de nota no mesmo quadrado.
struct ArtworkPanel: View {
    @ObservedObject var state: PlayerState
    @AppStorage(VisualMode.key) private var modeRaw = VisualMode.firstUse.rawValue
    @AppStorage(VideoCategoryStore.selectedKey) private var videoCategory = ""
    @ObservedObject private var videoStore = VideoCategoryStore.shared
    @State private var showVideoSettings = false
    @State private var showPicker = false
    /// Cantos de tudo o que aparece no quadro: capa, arte do skin, cenas e vídeos.
    static let corner: CGFloat = 8

    @Environment(\.theme) private var theme

    private var mode: VisualMode { VisualMode(rawValue: modeRaw) ?? .firstUse }

    var body: some View {
        Panel(title: panelTitle) {
            cover
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .padding(.horizontal, 12).padding(.top, 4).padding(.bottom, 12)
        }
    }

    private var panelTitle: LocalizedStringKey {
        switch mode {
        case .cover: "Capa"
        case .skinArt: "Arte"
        case .videos: "Vídeo"
        default: "Visual"
        }
    }

    /// Quadro quadrado fixo: o conteúdo preenche o quadro inteiro (cortando as sobras) e nunca muda o tamanho
    /// dele, seja capa grande, pequena, retangular, arte do skin, cena animada ou vídeo.
    private var cover: some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                ZStack {
                    LinearGradient(colors: [theme.artworkTint.opacity(0.9), theme.artworkTint.opacity(0.35)],
                                   startPoint: .top, endPoint: .bottom)
                    content
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: Self.corner, style: .continuous))
            .overlay(alignment: .topLeading) { formatBadge }
            .overlay(alignment: .topTrailing) { modeMenu }
    }

    @ViewBuilder private var content: some View {
        switch mode {
        case .cover: artwork
        case .skinArt: skinArtwork ?? AnyView(artwork)
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

    /// Menu no canto da capa: capa, cenas animadas e o submenu de vídeos por categoria.
    private var modeMenu: some View {
        Button { showPicker.toggle() } label: {
            Image(systemName: mode.symbol).font(.system(size: 11, weight: .semibold))
        }
        .buttonStyle(SkinButtonStyle(compact: true))
        .popover(isPresented: $showPicker, arrowEdge: .bottom) {
            VisualPicker(modeRaw: $modeRaw, videoCategory: $videoCategory, hasSkinArt: true) {
                DispatchQueue.main.async { showVideoSettings = true }
            }
        }
        .hint("O que mostrar aqui: \(mode.title)",
              "Capa da música (sem capa, aparece a arte do skin), Arte do skin, cenas animadas que reagem à música ou seus vídeos por categoria.")
        .padding(8)
        .accessibilityLabel("Escolher o que aparece no lugar da capa")
        .sheet(isPresented: $showVideoSettings) { MotionLibraryView(modeRaw: $modeRaw, videoCategory: $videoCategory) }
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
            VideoWall(clips: clips, trackKey: state.currentTrack?.id.seed ?? 0, cornerRadius: Self.corner)
                .overlay(alignment: .bottomLeading) {
                    Text(category?.name ?? "").font(.system(size: 10, weight: .semibold)).foregroundStyle(.white.opacity(0.85))
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(Capsule().fill(Color.black.opacity(0.4))).padding(8)
                }
        }
    }

    /// Ilustração do skin em uso (nil se o skin não tem).
    private var skinArtwork: AnyView? {
        guard let art = theme.art, let image = art.image(art.manifest.artwork) else { return nil }
        // Preenche o quadrado da capa sem vazar (foco no rosto, que fica na parte de cima).
        return AnyView(GeometryReader { geo in
            Image(nsImage: image).resizable().interpolation(.high).scaledToFill()
                .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
                .clipped()
        })
    }

    @ViewBuilder private var artwork: some View {
        if let image = state.cover {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .scaledToFill()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let skin = skinArtwork {
            skin
        } else {
            Image(systemName: "music.note")
                .font(.system(size: 90, weight: .regular))
                .foregroundStyle(Color.black.opacity(0.28))
        }
    }

    /// Formato do arquivo tocando (MP3, FLAC…) no canto superior esquerdo da capa.
    @ViewBuilder private var formatBadge: some View {
        if let ext = state.currentTrack?.url?.pathExtension, !ext.isEmpty {
            Text(ext.uppercased())
                .font(.system(size: 10, weight: .bold)).tracking(0.5)
                .foregroundStyle(.white)
                .padding(.horizontal, 7).padding(.vertical, 3)
                .background(Capsule().fill(Color.black.opacity(0.5)))
                .padding(8)
                .allowsHitTesting(false)
                .accessibilityLabel("Formato \(ext.uppercased())")
        }
    }
}
