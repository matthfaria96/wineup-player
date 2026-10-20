import SwiftUI

/// Botão de contorno fino, usado nas barras de controle.
struct ChromeButton<Label: View>: View {
    var isOn = false
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
    }
}

extension ChromeButton where Label == Image {
    init(symbol: String, isOn: Bool = false, action: @escaping () -> Void) {
        self.init(isOn: isOn, action: action) { Image(systemName: symbol) }
    }
}

extension ChromeButton where Label == Text {
    init(_ title: String, isOn: Bool = false, action: @escaping () -> Void) {
        self.init(isOn: isOn, action: action) { Text(title) }
    }
}
