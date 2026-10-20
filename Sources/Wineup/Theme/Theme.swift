import SwiftUI

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
}

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

    static let graphite = Theme(
        id: "graphite", name: "Grafite",
        windowTop: Color(hex: 0x1E1E20), windowBottom: Color(hex: 0x141416),
        panelFill: Color(hex: 0x252527, opacity: 0.92), panelBorder: Color.white.opacity(0.12),
        text: .white, mutedText: Color(hex: 0x9A9A9E), accent: Color(hex: 0xE5322D),
        rowSelection: Color.white.opacity(0.14), currentRow: Color(hex: 0xFF3B30),
        lyricsActive: .white, lyricsIdle: Color.white.opacity(0.78),
        control: Color(hex: 0xBDBDC2), artworkTint: Color(hex: 0x3A3A3E)
    )

    static let wine = Theme(
        id: "wine", name: "Vinho",
        windowTop: Color(hex: 0x4A1A1E), windowBottom: Color(hex: 0x24090D),
        panelFill: Color(hex: 0x5A1F25, opacity: 0.55), panelBorder: Color.white.opacity(0.15),
        text: Color(hex: 0xF6E9E9), mutedText: Color(hex: 0xC9A9AC), accent: Color(hex: 0xFF5A4D),
        rowSelection: Color.white.opacity(0.16), currentRow: Color(hex: 0xFFD27A),
        lyricsActive: Color(hex: 0xFFE3B0), lyricsIdle: Color(hex: 0xE9CFCF),
        control: Color(hex: 0xE2C4C6), artworkTint: Color(hex: 0x7A2A31)
    )

    static let green = Theme(
        id: "green", name: "Verde",
        windowTop: Color(hex: 0x0F2A26), windowBottom: Color(hex: 0x08181A),
        panelFill: Color(hex: 0x143530, opacity: 0.85), panelBorder: Color(hex: 0x7CE3A1, opacity: 0.28),
        text: Color(hex: 0x8FF0A8), mutedText: Color(hex: 0x5DBB7E), accent: Color(hex: 0xCFEFD9),
        rowSelection: Color(hex: 0x7CE3A1, opacity: 0.2), currentRow: Color(hex: 0xB6FFC8),
        lyricsActive: Color(hex: 0x9CFFB0), lyricsIdle: Color(hex: 0x7CE39A),
        control: Color(hex: 0x8FE3A8), artworkTint: Color(hex: 0x1F5C4A)
    )

    static let all: [Theme] = [.graphite, .wine, .green]

    static func named(_ id: String) -> Theme {
        all.first { $0.id == id } ?? .graphite
    }
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
