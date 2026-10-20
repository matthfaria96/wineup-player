import WineupCore
import SwiftUI

/// Linha de faixa usada na playlist e na busca.
struct TrackRow: View {
    let track: Track
    let index: Int
    let isCurrent: Bool
    let isSelected: Bool
    var showsDuration = true

    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: 6) {
            Text("\(index). \(track.displayName)")
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 4)
            if showsDuration {
                if let mark = track.mark {
                    Image(systemName: "heart.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(mark.color)
                }
                Text(Clock.format(track.duration))
                    .monospacedDigit()
                    .frame(width: 44, alignment: .trailing)
            }
        }
        .font(.system(size: 13))
        .foregroundStyle(isCurrent ? theme.currentRow : theme.text)
        .padding(.horizontal, 10)
        .frame(height: 24)
        .background(isSelected ? theme.rowSelection : Color.clear)
        .contentShape(Rectangle())
    }
}
