import WineupCore
import Combine
import WineupCore
import SwiftUI

struct PlayerPanel: View {
    @ObservedObject var state: PlayerState

    @StateObject private var meter = MeterModel()
    @Environment(\.theme) private var theme
    private let ticker = Timer.publish(every: 0.25, on: .main, in: .common).autoconnect()

    var body: some View {
        Panel(title: "Player") {
            VStack(alignment: .leading, spacing: 8) {
                header
                readout
                WaveformView(seed: state.currentTrack?.id.seed ?? 0, progress: state.progress, onSeek: state.seek(to:))
                    .frame(height: 26)
                    .opacity(state.currentTrack == nil ? 0.2 : 1)
                    .allowsHitTesting(state.currentTrack != nil)
                transport
                mixRow
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 10)
        }
        .onReceive(ticker) { _ in state.tick(0.25) }
        .onAppear { meter.start(tap: state.meter) }
        .onDisappear { meter.stop() }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(state.currentTrack?.title ?? "Nada tocando")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(theme.text)
                Text(state.currentTrack?.artist ?? " ")
                    .font(.system(size: 11))
                    .foregroundStyle(theme.mutedText)
            }
            .lineLimit(1)
            Spacer(minLength: 0)
            if let position = state.currentPosition {
                Text("\(position)/\(state.tracks.count)")
                    .font(.system(size: 10, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(theme.mutedText)
            }
        }
    }

    private var readout: some View {
        VStack(alignment: .trailing, spacing: 4) {
            // Duração total, pequena e apagada, acima do visor.
            HStack(spacing: 4) {
                Text("TOTAL").font(.system(size: 8, weight: .semibold)).tracking(0.8)
                Text(Self.lcdTotal(state.currentTrack?.duration ?? 0))
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
            }
            .foregroundStyle(Color(hex: 0xBFC8EE).opacity(0.6))
            // Barras e tempo restante com a mesma altura: topo e base na mesma linha.
            HStack(alignment: .center, spacing: 10) {
                LevelMeter(levels: meter.levels)
                    .frame(maxWidth: .infinity, alignment: .leading)
                SevenSegmentText(text: Self.lcdTime(state.remainingSeconds), digitHeight: LevelMeter.totalHeight)
                    .fixedSize()
                    .layoutPriority(1)
            }
            .frame(height: LevelMeter.totalHeight)
        }
    }

    /// "-MM:SS" com dois dígitos de minuto, como num visor LCD.
    static func lcdTime(_ seconds: Int) -> String {
        let s = max(seconds, 0)
        return String(format: "-%02d:%02d", min(s / 60, 99), s % 60)
    }

    static func lcdTotal(_ seconds: Int) -> String {
        let s = max(seconds, 0)
        return String(format: "%02d:%02d", min(s / 60, 99), s % 60)
    }

    private var transport: some View {
        HStack(spacing: 6) {
            ChromeButton(symbol: "backward.fill") { state.step(by: -1) }.frame(width: 38)
            ChromeButton(symbol: state.isPlaying ? "pause.fill" : "play.fill", isOn: state.isPlaying) { state.togglePlay() }
                .frame(width: 48)
            ChromeButton(symbol: "stop.fill") { state.stop() }.frame(width: 38)
            ChromeButton(symbol: "forward.fill") { state.step(by: 1) }.frame(width: 38)
            Spacer(minLength: 0)
            ChromeButton(symbol: "shuffle", isOn: state.shuffleOn) { state.shuffleOn.toggle() }
                .frame(width: 34).help(state.shuffleOn ? "Aleatório: ligado" : "Aleatório: desligado")
            ChromeButton(symbol: state.repeatMode == .one ? "repeat.1" : "repeat", isOn: state.repeatMode != .off) {
                state.repeatMode = { switch state.repeatMode { case .off: .all; case .all: .one; case .one: .off } }()
            }
            .frame(width: 34)
            .help(["off": "Repetir: desligado", "all": "Repetir: todas", "one": "Repetir: uma"][state.repeatMode.rawValue] ?? "")
            ChromeButton(symbol: "folder") { state.presentOpenPanel() }.frame(width: 34).help("Abrir arquivos ou pastas")
        }
    }

    private var mixRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "speaker.wave.2.fill").font(.system(size: 10)).foregroundStyle(theme.mutedText)
            ChromeSlider(value: $state.volume, knobThickness: 12).frame(height: 16)
            Text(String(format: "%.2g×", state.playbackRate))
                .font(.system(size: 10, weight: .medium)).monospacedDigit()
                .foregroundStyle(theme.mutedText)
                .frame(width: 30, alignment: .trailing)
                .help("Velocidade")
            ChromeSlider(value: $state.speed, knobThickness: 12).frame(width: 60, height: 16)
            Text("L R").font(.system(size: 9, weight: .semibold)).foregroundStyle(theme.mutedText)
                .help("Balanço")
            ChromeSlider(value: $state.balance, knobThickness: 12).frame(width: 44, height: 16)
        }
    }
}
