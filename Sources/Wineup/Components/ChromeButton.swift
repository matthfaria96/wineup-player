import SwiftUI

/// Botão de contorno fino, usado nas barras de controle.
struct ChromeButton<Label: View>: View {
    var isOn = false
    /// Nome lido pelo VoiceOver quando o rótulo é só um ícone.
    var spoken: String?
    let action: () -> Void
    @ViewBuilder var label: Label

    @Environment(\.theme) private var theme

    var body: some View {
        Button(action: action) {
            label
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(theme.text)
                .lineLimit(1)
                .padding(.horizontal, 7)
                .frame(minHeight: 22)
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isOn ? theme.rowSelection : Color.white.opacity(0.04))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(theme.control.opacity(0.75), lineWidth: 1)
                )
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
        case "backward.fill": "Anterior"
        case "forward.fill": "Próxima"
        case "play.fill": "Tocar"
        case "pause.fill": "Pausar"
        case "stop.fill": "Parar"
        case "shuffle": "Aleatório"
        case "repeat": "Repetir"
        case "repeat.1": "Repetir uma"
        case "folder": "Abrir arquivos"
        case "minus": "Diminuir"
        case "plus": "Aumentar"
        default: symbol
        }
    }
}

extension ChromeButton where Label == Text {
    init(_ title: String, isOn: Bool = false, action: @escaping () -> Void) {
        self.init(isOn: isOn, action: action) { Text(title) }
    }
}
