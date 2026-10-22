import SwiftUI

/// Medidor clássico: duas fileiras de barrinhas pré-desenhadas que acendem conforme o nível
/// (creme) e ficam vermelhas no fim (pico). Barras apagadas continuam visíveis.
struct LevelMeter: View {
    let levels: [Double]
    var segments = 24
    var redSegments = 3
    var yellowSegments = 6

    static let rowHeight: CGFloat = 15
    static let rowSpacing: CGFloat = 4
    /// Altura das duas fileiras juntas (o visor de tempo usa a mesma altura).
    static var totalHeight: CGFloat { rowHeight * 2 + rowSpacing }

    private let lit = Color(hex: 0xF3E2B8)
    private let peak = Color(hex: 0xE5322D)
    private let loud = Color(hex: 0xF2C230)

    var body: some View {
        // Um único Canvas (em vez de 48 views): barato de redesenhar 30× por segundo.
        Canvas { context, size in
            let gap: CGFloat = 2.5
            let width = max((size.width - gap * CGFloat(segments - 1)) / CGFloat(segments), 2)
            for (row, level) in [levels.first ?? 0, levels.count > 1 ? levels[1] : (levels.first ?? 0)].enumerated() {
                let y = CGFloat(row) * (Self.rowHeight + Self.rowSpacing)
                for index in 0..<segments {
                    let on = Double(index) / Double(segments) < level
                    let rect = CGRect(x: CGFloat(index) * (width + gap), y: y, width: width, height: Self.rowHeight)
                    context.fill(Path(roundedRect: rect, cornerRadius: 1),
                                 with: .color(zoneColor(index).opacity(on ? 1 : 0.14)))
                }
            }
        }
        .frame(minWidth: CGFloat(segments) * 6, maxWidth: CGFloat(segments) * 10.5)
        .frame(height: Self.totalHeight)
    }

    /// Creme (tema) até os sons altos, depois 6 amarelas e as 3 últimas vermelhas.
    private func zoneColor(_ index: Int) -> Color {
        if index >= segments - redSegments { return peak }
        if index >= segments - redSegments - yellowSegments { return loud }
        return lit
    }

}
