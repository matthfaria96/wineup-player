import SwiftUI

/// Slider com trilho fino e puxador retangular, horizontal ou vertical.
struct ChromeSlider: View {
    @Binding var value: Double
    var range: ClosedRange<Double> = 0...1
    var axis: Axis = .horizontal
    var knobLength: CGFloat = 10
    var knobThickness: CGFloat = 16

    @Environment(\.theme) private var theme

    /// Puxador: imagem do skin (centralizada, tamanho do skin) ou o retângulo padrão.
    @ViewBuilder private func knob(horizontal: Bool) -> some View {
        if let art = theme.art, let image = art.image(art.manifest.controls.knob) {
            let size = CGFloat(art.manifest.controls.knobSize ?? 20)
            Image(nsImage: image).resizable().interpolation(.high).frame(width: size, height: size)
        } else {
            RoundedRectangle(cornerRadius: 3)
                .fill(theme.control)
                .frame(width: horizontal ? knobLength : knobThickness, height: horizontal ? knobThickness : knobLength)
        }
    }

    /// Comprimento real do puxador no eixo: o do skin quando há imagem (senão o puxador
    /// passava do trilho nos extremos, ex.: presets com bandas em ±12 dB).
    private var effectiveKnobLength: CGFloat {
        if let art = theme.art, art.image(art.manifest.controls.knob) != nil {
            return CGFloat(art.manifest.controls.knobSize ?? 20)
        }
        return knobLength
    }

    var body: some View {
        GeometryReader { geo in
            let horizontal = axis == .horizontal
            let length = horizontal ? geo.size.width : geo.size.height
            let knobLength = effectiveKnobLength
            let travel = max(length - knobLength, 1)
            let span = range.upperBound - range.lowerBound
            let fraction = span == 0 ? 0 : (value - range.lowerBound) / span
            let along = knobLength / 2 + (horizontal ? fraction : 1 - fraction) * travel

            ZStack {
                Capsule()
                    .fill(theme.mutedText.opacity(0.45))
                    .frame(width: horizontal ? nil : 3, height: horizontal ? 3 : nil)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                knob(horizontal: horizontal)
                    .position(
                        x: horizontal ? along : geo.size.width / 2,
                        y: horizontal ? geo.size.height / 2 : along
                    )
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0).onChanged { drag in
                    let position = horizontal ? drag.location.x : drag.location.y
                    let raw = min(max((position - knobLength / 2) / travel, 0), 1)
                    let normalized = horizontal ? raw : 1 - raw
                    value = range.lowerBound + normalized * span
                }
            )
        }
        // VoiceOver: um controle ajustável (setas para cima/baixo); o nome vem de quem usa.
        .accessibilityElement()
        .accessibilityValue(spokenValue)
        .accessibilityAdjustableAction { direction in
            let step = (range.upperBound - range.lowerBound) / 20
            value = min(max(value + (direction == .increment ? step : -step), range.lowerBound), range.upperBound)
        }
    }

    private var spokenValue: String {
        if range.lowerBound < 0 { return String(format: "%+.0f dB", value) }
        let span = range.upperBound - range.lowerBound
        return "\(Int(((value - range.lowerBound) / max(span, 0.0001) * 100).rounded())) por cento"
    }
}
