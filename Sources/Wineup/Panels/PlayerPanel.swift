import Combine
import SwiftUI

struct PlayerPanel: View {
    @ObservedObject var state: PlayerState

    @Environment(\.theme) private var theme
    private let ticker = Timer.publish(every: 0.25, on: .main, in: .common).autoconnect()

    var body: some View {
        Panel(title: "AMP") {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 7) {
                    header
                    readout
                    sliders
                    WaveformView(seed: state.currentID, progress: state.progress, onSeek: state.seek(to:))
                        .frame(height: 30)
                    transport
                    footer
                }
                ChromeSlider(value: $state.volume, axis: .vertical, knobLength: 10, knobThickness: 20)
                    .frame(width: 22)
                    .padding(.top, 22)
                    .padding(.bottom, 70)
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 10)
        }
        .onReceive(ticker) { _ in state.tick(0.25) }
    }

    private var header: some View {
        HStack(spacing: 6) {
            Text(state.currentTrack.map { "\($0.title) - \($0.artist)" } ?? "—")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(theme.text)
                .lineLimit(1)
            Spacer(minLength: 0)
            ForEach(0..<2, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 3)
                    .stroke(theme.control, lineWidth: 1)
                    .frame(width: 13, height: 13)
            }
        }
    }

    private var readout: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 5) {
                LevelMeter(isPlaying: state.isPlaying)
                Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 2) {
                    GridRow {
                        Text("Play").foregroundStyle(theme.text)
                        Text("\(state.currentID)").foregroundStyle(theme.text)
                    }
                    GridRow {
                        Text("Stereo").foregroundStyle(theme.text)
                        Text("44").foregroundStyle(theme.text)
                    }
                }
                .font(.system(size: 11, weight: .semibold))
            }
            Spacer(minLength: 0)
            Text("-" + Clock.format(state.remainingSeconds).replacingOccurrences(of: ":", with: " : "))
                .font(.system(size: 30, weight: .ultraLight, design: .monospaced))
                .foregroundStyle(theme.text)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
    }

    private var sliders: some View {
        HStack(spacing: 8) {
            ChromeButton("−") { state.speed = max(state.speed - 0.05, 0) }
                .frame(width: 26)
            ChromeSlider(value: $state.speed, knobThickness: 14)
                .frame(height: 18)
            ChromeButton("+") { state.speed = min(state.speed + 0.05, 1) }
                .frame(width: 26)
            ChromeSlider(value: $state.balance, knobThickness: 14)
                .frame(width: 60, height: 18)
        }
    }

    private var transport: some View {
        HStack(spacing: 4) {
            ChromeButton(symbol: "backward.fill") { state.step(by: -1) }
            ChromeButton(symbol: "play.fill", isOn: state.isPlaying) { state.togglePlay() }
            ChromeButton(symbol: "pause.fill") { state.pause() }
            ChromeButton(symbol: "stop.fill") { state.stop() }
            ChromeButton(symbol: "forward.fill") { state.step(by: 1) }
            ChromeButton(symbol: "eject.fill") { state.presentOpenPanel() }
            ChromeButton(symbol: "repeat") {}
            ChromeButton(symbol: "checkmark") {}
            ChromeButton(symbol: "heart.text.square") {}
            ChromeButton(symbol: "gearshape") {}
        }
    }

    private var footer: some View {
        HStack(spacing: 6) {
            ChromeButton("List") {}.frame(width: 38)
            ChromeButton("Effects") {}.frame(width: 64)
            ColorDots(selection: $state.markFilter)
            Spacer(minLength: 0)
            ItemsCount(count: state.tracks.count)
        }
    }
}
