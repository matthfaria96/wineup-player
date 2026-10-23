import SwiftUI
import WineupLibrary

/// Volume atual (0...1) para as camadas animadas dos skins reagirem à música.
@MainActor
enum SkinEnergy {
    static weak var meter: MeterModel?

    static func value() -> Double {
        MainActor.assumeIsolated {
            let levels = meter?.levels ?? []
            return min(1, (levels.reduce(0, +) / Double(max(levels.count, 1))) * 1.4)
        }
    }
}

/// Moldura de painel: barra de título, fundo e borda. Com skin, o fundo é a arte do painel
/// (textura escurecida + camadas animadas) e a borda é a moldura de 9 fatias do skin.
struct Panel<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    @Environment(\.theme) private var theme
    @Environment(\.panelKind) private var kind

    private var style: SkinManifest.PanelStyle? { theme.art?.manifest.panelStyle(kind) }
    private var frame: (image: NSImage, inset: CGFloat)? { theme.art?.nineSlice(style?.frame) }
    private var radius: CGFloat { CGFloat(style?.cornerRadius ?? 9) }

    var body: some View {
        let inset = frame?.inset ?? 0
        VStack(spacing: 0) {
            if !title.isEmpty {
                Text(title)
                    .font(theme.art == nil ? .system(size: 12, weight: .medium) : theme.titleFont(12))
                    .foregroundStyle(theme.art == nil ? theme.mutedText : theme.text.opacity(0.9))
                    .shadow(color: .black.opacity(theme.art == nil ? 0 : 0.6), radius: 2, y: 1)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 10)
                    .frame(height: 24)
            }
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .padding(inset * 0.75)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            if let art = theme.art, style?.fill != nil || !(style?.layers.isEmpty ?? true) {
                ZStack {
                    theme.panelFill
                    SkinFillView(art: art, fill: style?.fill, layers: style?.layers ?? [], energy: SkinEnergy.value)
                }
            } else {
                theme.panelFill
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: radius))
        .overlay {
            if let frame {
                Image(nsImage: frame.image)
                    .resizable(capInsets: EdgeInsets(top: frame.inset, leading: frame.inset, bottom: frame.inset, trailing: frame.inset),
                               resizingMode: .stretch)
                    .allowsHitTesting(false)
            } else {
                RoundedRectangle(cornerRadius: radius).stroke(theme.panelBorder, lineWidth: 1)
            }
        }
    }
}

/// Texto "Playlist items: N" da base dos painéis.
struct ItemsCount: View {
    let count: Int

    @Environment(\.theme) private var theme

    var body: some View {
        Text("\(count) itens")
            .font(.system(size: 10.5))
            .foregroundStyle(theme.text)
            .lineLimit(1)
            .fixedSize()
    }
}
