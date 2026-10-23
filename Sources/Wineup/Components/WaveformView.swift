import SwiftUI

/// Forma de onda decorativa (gerada a partir do id da faixa) que também serve de barra de busca.
struct WaveformView: View {
    let seed: Int
    let progress: Double
    let onSeek: (Double) -> Void

    @Environment(\.theme) private var theme

    var body: some View {
        content
            .accessibilityElement()
            .accessibilityLabel("Posição da música")
            .accessibilityValue("\(Int((progress * 100).rounded())) por cento")
            .accessibilityAdjustableAction { direction in
                onSeek(min(max(progress + (direction == .increment ? 0.05 : -0.05), 0), 1))
            }
    }

    private var content: some View {
        GeometryReader { geo in
            Canvas { context, size in
                let barWidth: CGFloat = 2
                let gap: CGFloat = 1
                let count = Int(size.width / (barWidth + gap))
                for index in 0..<count {
                    let phase = Double(index) * 0.35 + Double(seed)
                    let envelope = 0.55 + 0.45 * sin(Double(index) * 0.05 + Double(seed))
                    let amplitude = abs(sin(phase) * cos(phase * 0.37 + 1.3)) * envelope
                    let height = max(size.height * (0.12 + 0.88 * amplitude), 2)
                    let x = CGFloat(index) * (barWidth + gap)
                    let rect = CGRect(x: x, y: (size.height - height) / 2, width: barWidth, height: height)
                    let played = Double(index) / Double(max(count, 1)) <= progress
                    context.fill(
                        Path(roundedRect: rect, cornerRadius: 1),
                        with: .color(played ? theme.accent : theme.accent.opacity(0.55))
                    )
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0).onChanged { drag in
                    onSeek(min(max(drag.location.x / max(geo.size.width, 1), 0), 1))
                }
            )
        }
    }
}
