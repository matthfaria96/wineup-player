import SwiftUI

/// Medidor clássico: duas fileiras de barrinhas pré-desenhadas que acendem conforme o nível
/// (creme) e ficam vermelhas no fim (pico). Barras apagadas continuam visíveis.
struct LevelMeter: View {
    let levels: [Double]
    var segments = 22
    var redSegments = 3

    private let lit = Color(hex: 0xF3E2B8)
    private let peak = Color(hex: 0xE5322D)

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            row(level: levels.first ?? 0)
            row(level: levels.count > 1 ? levels[1] : (levels.first ?? 0))
        }
    }

    private func row(level: Double) -> some View {
        HStack(spacing: 2) {
            ForEach(0..<segments, id: \.self) { index in
                let isPeak = index >= segments - redSegments
                let on = Double(index) / Double(segments) < level
                let color = isPeak ? peak : lit
                RoundedRectangle(cornerRadius: 1)
                    .fill(color.opacity(on ? 1 : 0.14))
                    .frame(width: 4, height: 14)
            }
        }
    }
}
