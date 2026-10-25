import AppKit
import SwiftUI

/// Fundo de janela do tema: vidro transparente no Glass; gradiente do skin com a arte e as camadas animadas.
struct ThemeBackground: View {
    let theme: Theme

    var body: some View {
        ZStack {
            if theme.isGlass {
                // Glass: a janela é transparente e mostra o que está atrás dela, desfocado.
                GlassBackdrop()
            } else {
                LinearGradient(colors: [theme.windowTop, theme.windowBottom], startPoint: .top, endPoint: .bottom)
            }
            // Skin: arte de fundo da janela e as camadas animadas (estrelas, redemoinhos...).
            if let art = theme.art, art.manifest.window.background != nil || !art.manifest.window.layers.isEmpty {
                SkinFillView(art: art, fill: art.manifest.window.background, layers: art.manifest.window.layers,
                             energy: SkinEnergy.value)
                // Leve escurecimento no topo (sem contorno): título e botões legíveis sobre a arte.
                VStack(spacing: 0) {
                    LinearGradient(colors: [.black.opacity(0.55), .black.opacity(0)], startPoint: .top, endPoint: .bottom)
                        .frame(height: 64)
                    Spacer(minLength: 0)
                }
            }
        }
        // Arte e animação do fundo nunca recebem cliques (o desenho assíncrono cria uma camada própria).
        .allowsHitTesting(false)
        .ignoresSafeArea()
    }
}

extension Theme {
    /// "Sem skin" escuro ou claro: as janelas de trabalho ficam no visual padrão do macOS.
    var isPlain: Bool { !isGlass && art == nil }
}

/// Janelas de trabalho (Metadados e as telas que abrem dela) com o tema escolhido:
/// fundo, cores, destaque e claro/escuro. A arte do skin fica parada aqui (gasta menos).
struct ThemedWindow: ViewModifier {
    @AppStorage(DisplayKeys.theme) private var themeID = Theme.defaultID

    func body(content: Content) -> some View {
        let theme = Theme.named(themeID)
        content
            .environment(\.theme, theme)
            .background {
                if !theme.isPlain {
                    ZStack {
                        ThemeBackground(theme: theme).environment(\.animationsPaused, true)
                        // Skin: véu da cor do painel, para a lista e os textos lerem bem sobre a arte.
                        if !theme.isGlass { theme.panelFill.opacity(0.55).ignoresSafeArea() }
                    }
                }
            }
            // Listas e formulários sem fundo próprio: o fundo do tema aparece por trás.
            .scrollContentBackground(theme.isPlain ? .automatic : .hidden)
            .tint(theme.isPlain ? nil : theme.accent)
            .background(WindowAccessor { ThemedWindowStyle.apply($0, theme: theme) })
            .preferredColorScheme(Theme.colorScheme(themeID: themeID))
    }
}

/// Superfície de painel nas janelas de trabalho (barra lateral, rodapé, área da lista).
struct ThemedSurface: ViewModifier {
    /// Lista: no Glass fica sem fundo (o vidro da janela aparece por trás).
    var list = false
    @Environment(\.theme) private var theme

    func body(content: Content) -> some View {
        if theme.isPlain {
            if list { content } else { content.background(.background.secondary) }
        } else if theme.isGlass {
            content.background(theme.ink.opacity(list ? 0 : 0.05))
        } else {
            content.background(theme.panelFill)
        }
    }
}

extension View {
    func themedWindow() -> some View { modifier(ThemedWindow()) }
    func themedSurface(list: Bool = false) -> some View { modifier(ThemedSurface(list: list)) }
}

/// Janela de trabalho: transparente no Glass; com tema (Glass ou skin), o fundo vai até atrás da barra de título.
@MainActor
enum ThemedWindowStyle {
    static func apply(_ window: NSWindow, theme: Theme) {
        GlassWindow.apply(window, glass: theme.isGlass)
        let themed = !theme.isPlain
        guard window.titlebarAppearsTransparent != themed else { return }
        window.titlebarAppearsTransparent = themed
        if themed { window.styleMask.insert(.fullSizeContentView) } else { window.styleMask.remove(.fullSizeContentView) }
    }
}

/// Dá acesso à NSWindow que hospeda a view.
struct WindowAccessor: NSViewRepresentable {
    let onWindow: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { if let w = view.window { onWindow(w) } }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { if let w = nsView.window { onWindow(w) } }
    }
}
