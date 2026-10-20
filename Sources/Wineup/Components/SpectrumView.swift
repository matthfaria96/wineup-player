import SwiftUI

/// Barras verticais do espectro (valores 0...1), mesmo estilo dos blocos do LevelMeter.
struct SpectrumView: View {
    let bands: [Double]

    var body: some View {
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(Array(bands.enumerated()), id: \.offset) { _, value in
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(Color.white.opacity(0.95))
                    .frame(width: 4, height: max(2, 34 * min(max(value, 0), 1)))
            }
        }
        .frame(height: 34, alignment: .bottom)
    }
}
