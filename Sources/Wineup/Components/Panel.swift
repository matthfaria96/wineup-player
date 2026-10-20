import SwiftUI

/// Moldura de painel: barra de título com bolinha, borda fina e cantos arredondados.
struct Panel<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    @Environment(\.theme) private var theme

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Text(title)
                    .font(.system(size: 12))
                    .foregroundStyle(theme.mutedText)
                HStack {
                    Circle()
                        .fill(theme.mutedText.opacity(0.55))
                        .frame(width: 10, height: 10)
                    Spacer()
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 24)

            content
        }
        .background(theme.panelFill)
        .clipShape(RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(theme.panelBorder, lineWidth: 1))
    }
}

/// Texto "Playlist items: N" da base dos painéis.
struct ItemsCount: View {
    let count: Int

    @Environment(\.theme) private var theme

    var body: some View {
        Text("Playlist items: \(count)")
            .font(.system(size: 10.5))
            .foregroundStyle(theme.text)
            .lineLimit(1)
            .fixedSize()
    }
}
