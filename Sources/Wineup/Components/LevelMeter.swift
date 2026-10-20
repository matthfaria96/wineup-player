import SwiftUI

/// Dois medidores de nível em blocos alimentados pelo `MeterModel` (níveis 0...1 por canal).
struct LevelMeter: View {
    let levels: [Double]
    private let segments = 12

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            row(level: levels.first ?? 0)
            row(level: levels.count > 1 ? levels[1] : (levels.first ?? 0))
        }
    }

    private func row(level: Double) -> some View {
        HStack(spacing: 2) {
            ForEach(0..<segments, id: \.self) { index in
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(Color.white.opacity(Double(index) / Double(segments) < level ? 0.95 : 0.18))
                    .frame(width: 9, height: 14)
            }
        }
    }
}
