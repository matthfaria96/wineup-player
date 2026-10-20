import SwiftUI

/// Dois medidores de nível em blocos; animam só enquanto "toca".
struct LevelMeter: View {
    let isPlaying: Bool
    private let segments = 12

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.1, paused: !isPlaying)) { timeline in
            let time = timeline.date.timeIntervalSinceReferenceDate
            VStack(alignment: .leading, spacing: 3) {
                row(level: isPlaying ? 0.55 + 0.4 * abs(sin(time * 3.1)) : 0.0)
                row(level: isPlaying ? 0.5 + 0.45 * abs(sin(time * 2.3 + 1)) : 0.0)
            }
        }
    }

    private func row(level: Double) -> some View {
        HStack(spacing: 2) {
            ForEach(0..<segments, id: \.self) { index in
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(Color.white.opacity(Double(index) / Double(segments) < level || !isPlaying ? 0.95 : 0.18))
                    .frame(width: 9, height: 14)
            }
        }
    }
}
