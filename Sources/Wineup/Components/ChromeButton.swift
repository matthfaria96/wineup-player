import AppKit
import SwiftUI

/// Botão de contorno fino, usado nas barras de controle.
struct ChromeButton<Label: View>: View {
    var isOn = false
    /// Nome lido pelo VoiceOver quando o rótulo é só um ícone.
    var spoken: String?
    let action: () -> Void
    @ViewBuilder var label: Label

    @Environment(\.theme) private var theme

    /// Botão desenhado pelo skin (normal / ligado), em 9 fatias.
    private var skinSlice: (image: NSImage, inset: CGFloat)? {
        guard let art = theme.art else { return nil }
        let c = art.manifest.controls
        return art.nineSlice(isOn ? (c.buttonOn ?? c.button) : c.button)
    }

    @ViewBuilder private var skinBackground: some View {
        if theme.isGlass {
            GlassControlBackground(on: isOn, radius: 8)
        } else if let s = skinSlice {
            Image(nsImage: s.image)
                .resizable(capInsets: EdgeInsets(top: s.inset, leading: s.inset, bottom: s.inset, trailing: s.inset), resizingMode: .stretch)
        } else {
            RoundedRectangle(cornerRadius: 6).fill(isOn ? theme.rowSelection : theme.ink.opacity(0.04))
        }
    }

    var body: some View {
        Button(action: action) {
            label
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(theme.art == nil && !(theme.isGlass && isOn) ? theme.text : (isOn ? theme.buttonTextOn : theme.buttonText))
                .lineLimit(1)
                .padding(.horizontal, 7)
                .frame(minHeight: 22)
                .frame(maxWidth: .infinity)
                .background { skinBackground }
                .overlay {
                    if skinSlice == nil, !theme.isGlass {
                        RoundedRectangle(cornerRadius: 6).stroke(theme.control.opacity(0.75), lineWidth: 1)
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
        .modifier(SpokenName(name: spoken))
    }
}

private struct SpokenName: ViewModifier {
    let name: String?
    func body(content: Content) -> some View {
        if let name { content.accessibilityLabel(name) } else { content }
    }
}

extension ChromeButton where Label == Image {
    init(symbol: String, isOn: Bool = false, action: @escaping () -> Void) {
        self.init(isOn: isOn, spoken: Self.spokenName(symbol), action: action) { Image(systemName: symbol) }
    }

    /// Nome lido pelo VoiceOver para os ícones usados nos controles.
    static func spokenName(_ symbol: String) -> String {
        switch symbol {
        case "backward.fill": String(localized: "Anterior")
        case "forward.fill": String(localized: "Próxima")
        case "play.fill": String(localized: "Tocar")
        case "pause.fill": String(localized: "Pausar")
        case "stop.fill": String(localized: "Parar")
        case "shuffle": String(localized: "Aleatório")
        case "repeat": String(localized: "Repetir")
        case "repeat.1": String(localized: "Repetir uma")
        case "folder": String(localized: "Abrir arquivos")
        case "minus": String(localized: "Diminuir")
        case "plus": String(localized: "Aumentar")
        default: symbol
        }
    }
}

extension ChromeButton where Label == Text {
    init(_ title: LocalizedStringKey, isOn: Bool = false, action: @escaping () -> Void) {
        self.init(isOn: isOn, action: action) { Text(title) }
    }
}
