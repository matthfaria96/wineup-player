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
        VStack(alignment: .leading, spacing: Self.rowSpacing) {
            row(level: levels.first ?? 0)
            row(level: levels.count > 1 ? levels[1] : (levels.first ?? 0))
        }
    }

    /// Creme (tema) até os sons altos, depois 6 amarelas e as 3 últimas vermelhas.
    private func zoneColor(_ index: Int) -> Color {
        if index >= segments - redSegments { return peak }
        if index >= segments - redSegments - yellowSegments { return loud }
        return lit
    }

    private func row(level: Double) -> some View {
        HStack(spacing: 2.5) {
            ForEach(0..<segments, id: \.self) { index in
                let on = Double(index) / Double(segments) < level
                let color = zoneColor(index)
                RoundedRectangle(cornerRadius: 1)
                    .fill(color.opacity(on ? 1 : 0.14))
                    .frame(minWidth: 4, maxWidth: 8)
                    .frame(height: Self.rowHeight)
            }
        }
    }
}
