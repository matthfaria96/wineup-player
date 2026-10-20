import SwiftUI

/// Moldura de painel: barra de título centralizada, borda fina e cantos arredondados.
struct Panel<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    @Environment(\.theme) private var theme

    var body: some View {
        VStack(spacing: 0) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(theme.mutedText)
                .lineLimit(1)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 10)
                .frame(height: 24)

            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
        Text("\(count) itens")
            .font(.system(size: 10.5))
            .foregroundStyle(theme.text)
            .lineLimit(1)
            .fixedSize()
    }
}
