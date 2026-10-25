import WineupCore
import SwiftUI

/// Bolinhas de marcação coloridas; tocar numa filtra a playlist, o X limpa.
struct ColorDots: View {
    @Binding var selection: MarkColor?

    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: 5) {
            ForEach(MarkColor.allCases) { mark in
                Circle()
                    .fill(mark.color)
                    .frame(width: 13, height: 13)
                    .overlay(Circle().stroke(theme.text.opacity(selection == mark ? 0.95 : 0), lineWidth: 2))
                    .onTapGesture { selection = selection == mark ? nil : mark }
                    .accessibilityElement()
                    .accessibilityLabel("Filtrar pela cor \(mark.displayName)")
                    .accessibilityAddTraits(selection == mark ? [.isButton, .isSelected] : .isButton)
                    .accessibilityAction { selection = selection == mark ? nil : mark }
            }
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 16))
                .foregroundStyle(theme.mutedText)
                .onTapGesture { selection = nil }
                .accessibilityLabel("Limpar filtro de cor")
                .accessibilityAddTraits(.isButton)
                .accessibilityAction { selection = nil }
        }
    }
}
