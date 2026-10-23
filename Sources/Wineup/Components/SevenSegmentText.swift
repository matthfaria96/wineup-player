import SwiftUI

/// Texto em estilo LCD de 7 segmentos (dígitos, "-" e ":"), desenhado com formas.
/// Segmentos apagados ficam levemente visíveis, como num visor real.
struct SevenSegmentText: View {
    let text: String
    var digitHeight: CGFloat = 30
    var color = Color(hex: 0xBFC8EE)

    private var digitWidth: CGFloat { digitHeight * 0.55 }
    private var thickness: CGFloat { max(digitHeight * 0.11, 2) }

    var body: some View {
        HStack(spacing: digitHeight * 0.12) {
            ForEach(Array(text.enumerated()), id: \.offset) { _, ch in
                glyph(ch)
            }
        }
        .accessibilityElement()
        .accessibilityLabel(text.hasPrefix("-") ? "Tempo restante" : "Tempo")
        .accessibilityValue(text.trimmingCharacters(in: CharacterSet(charactersIn: "-")))
    }

    @ViewBuilder private func glyph(_ ch: Character) -> some View {
        if ch == ":" {
            VStack(spacing: digitHeight * 0.28) {
                dot; dot
            }
            .frame(width: thickness * 1.6, height: digitHeight)
        } else {
            Canvas { context, size in
                let on = Self.segments(for: ch)
                for (index, path) in segmentPaths(in: size).enumerated() {
                    let ghost = ch == "-" ? 0 : 0.07   // o sinal de menos não tem "8" fantasma
                    context.fill(path, with: .color(color.opacity(on.contains(index) ? 1 : ghost)))
                }
            }
            .frame(width: digitWidth, height: digitHeight)
        }
    }

    private var dot: some View {
        RoundedRectangle(cornerRadius: 1).fill(color).frame(width: thickness, height: thickness)
    }

    /// Segmentos a b c d e f g (0...6) acesos para cada caractere.
    private static func segments(for ch: Character) -> Set<Int> {
        switch ch {
        case "0": [0, 1, 2, 3, 4, 5]
        case "1": [1, 2]
        case "2": [0, 1, 6, 4, 3]
        case "3": [0, 1, 6, 2, 3]
        case "4": [5, 6, 1, 2]
        case "5": [0, 5, 6, 2, 3]
        case "6": [0, 5, 6, 4, 2, 3]
        case "7": [0, 1, 2]
        case "8": [0, 1, 2, 3, 4, 5, 6]
        case "9": [0, 1, 2, 3, 5, 6]
        case "-": [6]
        default: []
        }
    }

    /// Hexágonos alongados para os 7 segmentos, com pequenos vãos entre eles.
    private func segmentPaths(in size: CGSize) -> [Path] {
        let w = size.width, h = size.height, t = thickness, g = t * 0.25
        func horizontal(_ y: CGFloat) -> Path {
            Path { p in
                p.move(to: CGPoint(x: g + t / 2, y: y))
                p.addLine(to: CGPoint(x: g + t, y: y - t / 2))
                p.addLine(to: CGPoint(x: w - g - t, y: y - t / 2))
                p.addLine(to: CGPoint(x: w - g - t / 2, y: y))
                p.addLine(to: CGPoint(x: w - g - t, y: y + t / 2))
                p.addLine(to: CGPoint(x: g + t, y: y + t / 2))
                p.closeSubpath()
            }
        }
        func vertical(_ x: CGFloat, _ y0: CGFloat, _ y1: CGFloat) -> Path {
            Path { p in
                p.move(to: CGPoint(x: x, y: y0 + g))
                p.addLine(to: CGPoint(x: x + t / 2, y: y0 + g + t / 2))
                p.addLine(to: CGPoint(x: x + t / 2, y: y1 - g - t / 2))
                p.addLine(to: CGPoint(x: x, y: y1 - g))
                p.addLine(to: CGPoint(x: x - t / 2, y: y1 - g - t / 2))
                p.addLine(to: CGPoint(x: x - t / 2, y: y0 + g + t / 2))
                p.closeSubpath()
            }
        }
        let top = t / 2, mid = h / 2, bottom = h - t / 2
        let left = t / 2, right = w - t / 2
        return [
            horizontal(top),                 // a
            vertical(right, top, mid),       // b
            vertical(right, mid, bottom),    // c
            horizontal(bottom),              // d
            vertical(left, mid, bottom),     // e
            vertical(left, top, mid),        // f
            horizontal(mid),                 // g
        ]
    }
}
