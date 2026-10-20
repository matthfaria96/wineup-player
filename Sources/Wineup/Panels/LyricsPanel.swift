import SwiftUI

struct LyricsPanel: View {
    @ObservedObject var state: PlayerState

    @Environment(\.theme) private var theme

    var body: some View {
        Panel(title: "Lyrics") {
            VStack(spacing: 6) {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: 14) {
                            ForEach(Array(state.lyricLines.enumerated()), id: \.offset) { index, line in
                                Text(line)
                                    .font(.system(size: 19 * state.lyricsScale, weight: index == state.activeLyricIndex ? .semibold : .regular))
                                    .foregroundStyle(index == state.activeLyricIndex ? theme.lyricsActive : theme.lyricsIdle.opacity(0.8))
                                    .multilineTextAlignment(.center)
                                    .id(index)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 20)
                    }
                    .onChange(of: state.activeLyricIndex) { _, index in
                        withAnimation { proxy.scrollTo(index, anchor: .center) }
                    }
                }
                HStack(spacing: 6) {
                    sizeButton(size: 10) { state.lyricsScale = max(state.lyricsScale - 0.1, 0.6) }
                    sizeButton(size: 14) { state.lyricsScale = min(state.lyricsScale + 0.1, 1.6) }
                }
                .padding(.bottom, 8)
            }
        }
    }

    private func sizeButton(size: CGFloat, action: @escaping () -> Void) -> some View {
        ChromeButton(action: action) {
            Text("A").font(.system(size: size, weight: .semibold))
        }
        .frame(width: 34)
    }
}
