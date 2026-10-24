import AppKit
import CoreText
import SwiftUI
import WineupLibrary

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255, opacity: opacity)
    }

    /// "#RRGGBB" ou "#RRGGBBAA".
    init?(hexString: String) {
        var s = hexString.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6 || s.count == 8, let v = UInt64(s, radix: 16) else { return nil }
        let hasAlpha = s.count == 8
        self.init(hex: UInt32(hasAlpha ? v >> 8 : v), opacity: hasAlpha ? Double(v & 0xFF) / 255 : 1)
    }

    var hexString: String {
        let c = NSColor(self).usingColorSpace(.sRGB) ?? .black
        let r = Int((c.redComponent * 255).rounded()), g = Int((c.greenComponent * 255).rounded())
        let b = Int((c.blueComponent * 255).rounded()), a = Int((c.alphaComponent * 255).rounded())
        return a == 255 ? String(format: "#%02X%02X%02X", r, g, b) : String(format: "#%02X%02X%02X%02X", r, g, b, a)
    }
}

/// Arte de um skin carregada (imagens em cache, fontes registradas). Uma por skin/versão.
final class SkinArt {
    let manifest: SkinManifest
    let folder: URL
    private var images: [String: NSImage] = [:]
    private var slices: [String: NSImage] = [:]
    private static var cache: [String: (revision: Int, art: SkinArt)] = [:]
    private static var registeredFonts = Set<String>()

    private init(_ skin: Skin) {
        manifest = skin.manifest
        folder = skin.folder
        for f in manifest.fonts {
            let url = folder.appendingPathComponent(f)
            guard !Self.registeredFonts.contains(url.path) else { continue }
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
            Self.registeredFonts.insert(url.path)
        }
    }

    /// Mesmo skin (pasta) na mesma versão da loja = mesma instância (as imagens não são relidas a cada desenho).
    /// Uma entrada por pasta: ao salvar/recarregar, a arte antiga é trocada (o cache não cresce).
    static func of(_ skin: Skin) -> SkinArt {
        let revision = SkinStore.shared.revision
        if let hit = cache[skin.folder.path], hit.revision == revision, hit.art.manifest == skin.manifest { return hit.art }
        let art = SkinArt(skin)
        cache[skin.folder.path] = (revision, art)
        return art
    }

    func image(_ name: String?) -> NSImage? {
        guard let name, !name.isEmpty else { return nil }
        if let hit = images[name] { return hit }
        let img = NSImage(contentsOf: folder.appendingPathComponent(name))
        images[name] = img
        return img
    }

    /// Imagem de 9 fatias no tamanho de desenho: a borda fica com `width` pontos.
    func nineSlice(_ s: SkinManifest.NineSlice?) -> (image: NSImage, inset: CGFloat)? {
        guard let s else { return nil }
        let key = "\(s.image)|\(s.slice)|\(s.width)"
        if let hit = slices[key] { return (hit, CGFloat(s.width)) }
        guard let base = image(s.image), let rep = base.representations.first else { return nil }
        let scale = s.width / s.slice
        // Cópia redimensionada uma vez só (antes era feita a cada desenho).
        let sized = base.copy() as! NSImage
        sized.size = NSSize(width: Double(rep.pixelsWide) * scale, height: Double(rep.pixelsHigh) * scale)
        slices[key] = sized
        return (sized, CGFloat(s.width))
    }

    func font(_ ref: SkinManifest.FontRef?, size: CGFloat, fallbackWeight: Font.Weight) -> Font? {
        guard let ref else { return nil }
        let weight: Font.Weight = switch ref.weight {
        case "light": .light
        case "medium": .medium
        case "semibold": .semibold
        case "bold": .bold
        case "black": .heavy
        default: fallbackWeight
        }
        return Font.custom(ref.name, size: size).weight(weight)
    }
}

/// Tema pronto para desenhar: cores do skin + a arte (fundos, molduras, botões, camadas animadas).
struct Theme: Identifiable, Equatable {
    let id: String
    let name: String
    let windowTop: Color
    let windowBottom: Color
    let panelFill: Color
    let panelBorder: Color
    let text: Color
    let mutedText: Color
    let accent: Color
    let rowSelection: Color
    let currentRow: Color
    let lyricsActive: Color
    let lyricsIdle: Color
    let control: Color
    let artworkTint: Color
    let display: Color
    let buttonText: Color
    let buttonTextOn: Color
    let meterLow: Color
    let meterMid: Color
    let meterPeak: Color
    let art: SkinArt?

    init(manifest: SkinManifest, art: SkinArt?) {
        func c(_ key: SkinManifest.ColorToken) -> Color {
            Color(hexString: manifest.colors[key.rawValue] ?? "") ?? Color(hexString: SkinManifest.fallbackColors[key.rawValue]!)!
        }
        id = manifest.id; name = manifest.name
        windowTop = c(.windowTop); windowBottom = c(.windowBottom); panelFill = c(.panelFill)
        panelBorder = c(.panelBorder); text = c(.text); mutedText = c(.mutedText); accent = c(.accent)
        rowSelection = c(.rowSelection); currentRow = c(.currentRow); lyricsActive = c(.lyricsActive)
        lyricsIdle = c(.lyricsIdle); control = c(.control); artworkTint = c(.artworkTint); display = c(.display)
        buttonText = manifest.colors["buttonText"].flatMap(Color.init(hexString:)) ?? c(.text)
        buttonTextOn = manifest.colors["buttonTextOn"].flatMap(Color.init(hexString:)) ?? buttonText
        meterLow = c(.meterLow); meterMid = c(.meterMid); meterPeak = c(.meterPeak)
        self.art = art
    }

    init(_ skin: Skin) { self.init(manifest: skin.manifest, art: SkinArt.of(skin)) }

    static func == (a: Theme, b: Theme) -> Bool { a.id == b.id && a.art === b.art }

    /// Sem nenhum skin instalado (não deve acontecer): cores neutras, sem arte.
    static let plain = Theme(manifest: SkinManifest(id: "none", name: String(localized: "Sem skin")), art: nil)
    static let graphite = plain

    /// Temas de todos os skins, montados uma vez por versão da loja (e não a cada desenho da janela).
    static var all: [Theme] {
        let store = SkinStore.shared
        if let cached = allCache, cached.revision == store.revision { return cached.themes }
        let themes = store.skins.map(Theme.init)
        allCache = (store.revision, themes)
        return themes
    }

    private static var allCache: (revision: Int, themes: [Theme])?

    /// Id para o visual padrão do app, sem skin.
    static let noneID = "none"

    static func named(_ id: String) -> Theme {
        if id == noneID { return plain }
        let themes = all
        return themes.first { $0.id == id } ?? themes.first { $0.id == SkinStore.defaultID } ?? themes.first ?? plain
    }

    /// Fonte dos títulos do skin (ou a do sistema).
    /// `size` do skin = tamanho de referência para 12 pt (fonte pixel pede menor; serifada pede maior).
    func titleFont(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        guard let art, let ref = art.manifest.titleFont else { return .system(size: size, weight: weight) }
        let factor = (ref.size ?? 13.8) / 12
        return art.font(ref, size: size * factor, fallbackWeight: weight) ?? .system(size: size, weight: weight)
    }
}

private struct ThemeKey: EnvironmentKey {
    static let defaultValue = Theme.plain
}

extension EnvironmentValues {
    var theme: Theme {
        get { self[ThemeKey.self] }
        set { self[ThemeKey.self] = newValue }
    }
}

/// Qual painel está sendo desenhado ("player", "equalizer", "playlist", "artwork", "lyrics").
private struct PanelKindKey: EnvironmentKey { static let defaultValue = "default" }

extension EnvironmentValues {
    var panelKind: String {
        get { self[PanelKindKey.self] }
        set { self[PanelKindKey.self] = newValue }
    }
}
