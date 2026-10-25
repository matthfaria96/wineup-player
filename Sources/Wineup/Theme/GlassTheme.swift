import AppKit
import SwiftUI
import WineupLibrary

extension Theme {
    /// Id do tema nativo da Apple (vidro e transparência, escuro). É o tema padrão do app.
    static let glassID = "glass"
    /// "Sem skin" claro (o "Sem skin" de sempre, `noneID`, é o escuro).
    static let noneLightID = "none-light"
    /// Tema de quem abre o Wineup pela primeira vez.
    static let defaultID = glassID

    /// Temas do próprio app (não são skins instalados).
    static func isBuiltIn(_ id: String) -> Bool { id == glassID || id == noneID || id == noneLightID }

    /// Glass: vidro escuro da Apple, o vermelho-vinho do Wineup como destaque,
    /// e o visor LCD e o medidor clássicos mantidos.
    static let glass = Theme(glass: builtInManifest(glassID, String(localized: "Glass"), colors: [
        "windowTop": "#1C1C1E", "windowBottom": "#141416", "panelFill": "#FFFFFF0D", "panelBorder": "#FFFFFF24",
        "text": "#FFFFFF", "mutedText": "#FFFFFF99", "accent": "#E5322D", "rowSelection": "#FFFFFF1F",
        "currentRow": "#FF453A", "lyricsActive": "#FFFFFF", "lyricsIdle": "#FFFFFF8C", "control": "#FFFFFFD9",
        "artworkTint": "#FFFFFF14", "display": "#BFC8EE", "buttonText": "#FFFFFF", "buttonTextOn": "#FFFFFF",
        "meterLow": "#F3E2B8", "meterMid": "#F2C230", "meterPeak": "#FF453A"]))

    /// "Sem skin" claro: o mesmo visual simples, em cinza-claro e branco (visor e medidor em tons escuros).
    static let plainLight = Theme(plainLight: builtInManifest(noneLightID, String(localized: "Sem skin claro"), colors: [
        "windowTop": "#ECECEE", "windowBottom": "#E1E1E4", "panelFill": "#FFFFFFEB", "panelBorder": "#0000001A",
        "text": "#1D1D1F", "mutedText": "#6E6E73", "accent": "#D62E2A", "rowSelection": "#0000001A",
        "currentRow": "#D62E2A", "lyricsActive": "#1D1D1F", "lyricsIdle": "#1D1D1FB3", "control": "#8E8E93",
        "artworkTint": "#0000000F", "display": "#262B45", "buttonText": "#1D1D1F", "buttonTextOn": "#1D1D1F",
        "meterLow": "#B79A62", "meterMid": "#E3A600", "meterPeak": "#D62E2A"]))

    private static func builtInManifest(_ id: String, _ name: String, colors: [String: String]) -> SkinManifest {
        var manifest = SkinManifest(id: id, name: name)
        manifest.colors = colors
        return manifest
    }

    /// Esquema de cores das janelas: claro só com o "Sem skin claro"; Glass e skins são escuros.
    static func colorScheme(themeID: String) -> ColorScheme {
        themeID == noneLightID ? .light : .dark
    }
}

/// Põe a janela no esquema de cores do tema escolhido.
struct WineupColorScheme: ViewModifier {
    @AppStorage(DisplayKeys.theme) private var themeID = Theme.defaultID

    func body(content: Content) -> some View {
        content.preferredColorScheme(Theme.colorScheme(themeID: themeID))
    }
}

extension View {
    func wineupColorScheme() -> some View { modifier(WineupColorScheme()) }
}

// MARK: - Fundo da janela

/// Fundo translúcido da janela no Glass: o que está atrás da janela aparece desfocado,
/// com um brilho vinho bem leve nos cantos (a cor do Wineup).
struct GlassBackdrop: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ZStack {
            BehindWindowBlur()
            let dark = scheme == .dark
            // Véu: mantém o texto legível sobre qualquer papel de parede.
            (dark ? Color.black.opacity(0.18) : Color.white.opacity(0.22))
            RadialGradient(colors: [Color(hex: 0x8E1B2A, opacity: dark ? 0.30 : 0.10), .clear],
                           center: .topLeading, startRadius: 0, endRadius: 720)
            RadialGradient(colors: [Color(hex: 0xC2410C, opacity: dark ? 0.14 : 0.06), .clear],
                           center: .bottomTrailing, startRadius: 0, endRadius: 640)
        }
    }
}

/// NSVisualEffectView que mistura com o que está atrás da janela (sempre ativo, mesmo sem foco).
private struct BehindWindowBlur: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.blendingMode = .behindWindow
        view.material = .underWindowBackground
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

/// Janela transparente só no Glass (os outros temas pintam o próprio fundo, opaco).
@MainActor
enum GlassWindow {
    static func apply(_ window: NSWindow, glass: Bool) {
        guard window.isOpaque == glass else { return }
        window.isOpaque = !glass
        window.backgroundColor = glass ? .clear : .windowBackgroundColor
        window.invalidateShadow()
    }
}

// MARK: - Superfícies de vidro

/// Onde o controle está: na barra do topo (sobre o fundo da janela) ou dentro de um painel.
/// No topo os botões são de vidro; dentro dos painéis (que já são de vidro) são preenchidos, como no macOS.
private struct OnWindowChromeKey: EnvironmentKey { static let defaultValue = false }

extension EnvironmentValues {
    var onWindowChrome: Bool {
        get { self[OnWindowChromeKey.self] }
        set { self[OnWindowChromeKey.self] = newValue }
    }
}

extension View {
    /// Vidro da Apple (macOS 26+) numa forma; antes disso, material translúcido com borda fina.
    @ViewBuilder
    func glassSurface<S: InsettableShape>(_ shape: S, interactive: Bool = false, tint: Color? = nil) -> some View {
        if #available(macOS 26, *) {
            modifier(LiquidGlass(shape: shape, interactive: interactive, tint: tint))
        } else {
            modifier(MaterialGlass(shape: shape, tint: tint))
        }
    }

    /// Painel de vidro com cantos contínuos (padrão do macOS atual).
    /// No escuro, o vidro leva um tom mais fundo: os painéis se destacam do fundo da janela.
    func glassPanel(radius: CGFloat, dark: Bool) -> some View {
        glassSurface(RoundedRectangle(cornerRadius: radius, style: .continuous), tint: dark ? Color.black.opacity(0.22) : nil)
    }
}

@available(macOS 26, *)
private struct LiquidGlass<S: InsettableShape>: ViewModifier {
    let shape: S
    let interactive: Bool
    let tint: Color?

    func body(content: Content) -> some View {
        content.glassEffect(Glass.regular.tint(tint).interactive(interactive), in: shape)
    }
}

private struct MaterialGlass<S: InsettableShape>: ViewModifier {
    let shape: S
    let tint: Color?
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        content
            .background {
                ZStack {
                    shape.fill(.ultraThinMaterial)
                    if let tint { shape.fill(tint.opacity(0.55)) }
                }
            }
            .overlay {
                shape.strokeBorder(LinearGradient(colors: [Color.white.opacity(scheme == .dark ? 0.22 : 0.7),
                                                           Color.white.opacity(scheme == .dark ? 0.06 : 0.25)],
                                                  startPoint: .top, endPoint: .bottom), lineWidth: 0.75)
                    .allowsHitTesting(false)
            }
            .shadow(color: .black.opacity(scheme == .dark ? 0.25 : 0.08), radius: 10, y: 4)
    }
}

/// Fundo de controle do Glass: vidro na barra do topo; dentro dos painéis, cápsula preenchida
/// (ligado = vermelho-vinho do Wineup com texto branco).
struct GlassControlBackground: View {
    var on: Bool
    var radius: CGFloat?
    @Environment(\.theme) private var theme
    @Environment(\.onWindowChrome) private var onWindowChrome

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: radius ?? 8, style: .continuous)
        if onWindowChrome {
            // Barra do topo: cápsulas de vidro, como os botões da barra de ferramentas do macOS.
            Color.clear.glassSurface(Capsule(), interactive: true, tint: on ? theme.accent : nil)
        } else {
            shape.fill(on ? AnyShapeStyle(theme.accent) : AnyShapeStyle(theme.ink.opacity(theme.isLight ? 0.06 : 0.1)))
                .overlay(shape.strokeBorder(theme.ink.opacity(on ? 0 : (theme.isLight ? 0.08 : 0.06)), lineWidth: 0.5))
        }
    }
}
