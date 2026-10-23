import SwiftUI
import WineupAudio
import WineupCore

/// Forma de onda real da música (volume de cada trecho, lido do arquivo) que também serve de barra de busca.
/// Enquanto a música é lida, mostra uma linha fina.
struct WaveformView: View {
    let url: URL?
    let progress: Double
    let onSeek: (Double) -> Void

    @Environment(\.theme) private var theme
    @State private var heights: [Float] = []

    var body: some View {
        content
            .accessibilityElement()
            .accessibilityLabel("Posição da música")
            .accessibilityValue("\(Int((progress * 100).rounded())) por cento")
            .accessibilityAdjustableAction { direction in
                onSeek(min(max(progress + (direction == .increment ? 0.05 : -0.05), 0), 1))
            }
            .task(id: url) {
                heights = []
                guard let url else { return }
                let loaded = await Task.detached(priority: .utility) {
                    WaveformAnalyzer.shared.levels(url).map { Waveform.heights($0) } ?? []
                }.value
                guard !Task.isCancelled else { return }
                withAnimation(.easeOut(duration: 0.35)) { heights = loaded }
            }
    }

    private var content: some View {
        GeometryReader { geo in
            Canvas { context, size in
                let barWidth: CGFloat = 2
                let gap: CGFloat = 1
                let count = max(Int(size.width / (barWidth + gap)), 1)
                for index in 0..<count {
                    let amplitude = Double(bar(index, of: count))
                    let height = max(size.height * (0.08 + 0.92 * amplitude), 2)
                    let x = CGFloat(index) * (barWidth + gap)
                    let rect = CGRect(x: x, y: (size.height - height) / 2, width: barWidth, height: height)
                    let played = Double(index) / Double(count) <= progress
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

    /// Maior altura entre os trechos que caem nesta barra (o pico do trecho, para os graves aparecerem).
    private func bar(_ index: Int, of count: Int) -> Float {
        guard !heights.isEmpty else { return 0 }
        let lo = index * heights.count / count
        let hi = max(lo + 1, (index + 1) * heights.count / count)
        return heights[min(lo, heights.count - 1)..<min(hi, heights.count)].max() ?? 0
    }
}
