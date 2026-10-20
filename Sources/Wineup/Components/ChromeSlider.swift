import SwiftUI

/// Slider com trilho fino e puxador retangular, horizontal ou vertical.
struct ChromeSlider: View {
    @Binding var value: Double
    var range: ClosedRange<Double> = 0...1
    var axis: Axis = .horizontal
    var knobLength: CGFloat = 10
    var knobThickness: CGFloat = 16

    @Environment(\.theme) private var theme

    var body: some View {
        GeometryReader { geo in
            let horizontal = axis == .horizontal
            let length = horizontal ? geo.size.width : geo.size.height
            let travel = max(length - knobLength, 1)
            let span = range.upperBound - range.lowerBound
            let fraction = span == 0 ? 0 : (value - range.lowerBound) / span
            let along = knobLength / 2 + (horizontal ? fraction : 1 - fraction) * travel

            ZStack {
                Capsule()
                    .fill(theme.mutedText.opacity(0.45))
                    .frame(width: horizontal ? nil : 3, height: horizontal ? 3 : nil)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                RoundedRectangle(cornerRadius: 3)
                    .fill(theme.control)
                    .frame(
                        width: horizontal ? knobLength : knobThickness,
                        height: horizontal ? knobThickness : knobLength
                    )
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
    }
}
