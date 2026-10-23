import AppKit
import SwiftUI
import WineupLibrary

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }

    /// "#RRGGBB" ou "#RRGGBBAA" (formato dos arquivos de tema).
    init?(hexString: String) {
        var s = hexString.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6 || s.count == 8, let v = UInt64(s, radix: 16) else { return nil }
        let hasAlpha = s.count == 8
        let rgb = hasAlpha ? v >> 8 : v
        let alpha = hasAlpha ? Double(v & 0xFF) / 255 : 1
        self.init(hex: UInt32(rgb), opacity: alpha)
    }

    var hexString: String {
        let c = NSColor(self).usingColorSpace(.sRGB) ?? .black
        let r = Int((c.redComponent * 255).rounded()), g = Int((c.greenComponent * 255).rounded())
        let b = Int((c.blueComponent * 255).rounded()), a = Int((c.alphaComponent * 255).rounded())
        return a == 255 ? String(format: "#%02X%02X%02X", r, g, b) : String(format: "#%02X%02X%02X%02X", r, g, b, a)
    }
}

/// Tema pronto para desenhar (cores já convertidas). Vem de um `ThemeFile`.
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

    init(_ file: ThemeFile) {
        func c(_ key: ThemeFile.Token) -> Color {
            Color(hexString: file.colors[key.rawValue] ?? "") ?? Color(hexString: ThemeFile.graphite.colors[key.rawValue]!)!
        }
        id = file.id; name = file.name
        windowTop = c(.windowTop); windowBottom = c(.windowBottom); panelFill = c(.panelFill)
        panelBorder = c(.panelBorder); text = c(.text); mutedText = c(.mutedText); accent = c(.accent)
        rowSelection = c(.rowSelection); currentRow = c(.currentRow); lyricsActive = c(.lyricsActive)
        lyricsIdle = c(.lyricsIdle); control = c(.control); artworkTint = c(.artworkTint); display = c(.display)
    }

    static let graphite = Theme(.graphite)
    static var all: [Theme] { ThemeStore.shared.files.map(Theme.init) }

    static func named(_ id: String) -> Theme { ThemeStore.shared.theme(id) }
}

private struct ThemeKey: EnvironmentKey {
    static let defaultValue = Theme.graphite
}

extension EnvironmentValues {
    var theme: Theme {
        get { self[ThemeKey.self] }
        set { self[ThemeKey.self] = newValue }
    }
}
