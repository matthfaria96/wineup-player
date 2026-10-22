import WineupAudio
import WineupCore
import Combine
import WineupCore
import SwiftUI

struct PlayerPanel: View {
    @ObservedObject var state: PlayerState
    @ObservedObject private var clock: PlaybackClock

    init(state: PlayerState) {
        self.state = state
        self.clock = state.clock
    }

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
                LiveMeter(meter: state.meterModel, tap: state.meter)
                    .frame(maxWidth: .infinity, alignment: .leading)
                SevenSegmentText(text: Self.lcdTime(state.remainingSeconds), digitHeight: LevelMeter.totalHeight)
                    .fixedSize()
                    .layoutPriority(1)
            }
            .frame(height: LevelMeter.totalHeight)
        }
    }

    /// "-MM:SS" com dois dígitos de minuto, como num visor LCD.
    static func lcdTime(_ seconds: Int) -> String { Clock.lcd(seconds, negative: true) }

    static func lcdTotal(_ seconds: Int) -> String { Clock.lcd(seconds) }

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
            // Velocidade: 0,5× a 2× em passos de 0,25 (clique no valor volta a 1×).
            HStack(spacing: 2) {
                ChromeButton(symbol: "minus") { state.changeRate(by: -1) }.frame(width: 20)
                    .disabled(state.playbackRate <= 0.5)
                Text(Self.rateText(state.playbackRate))
                    .font(.system(size: 10, weight: .semibold)).monospacedDigit()
                    .foregroundStyle(state.playbackRate == 1 ? theme.mutedText : theme.accent)
                    .frame(width: 36)
                    .contentShape(Rectangle())
                    .onTapGesture { state.playbackRate = 1 }
                ChromeButton(symbol: "plus") { state.changeRate(by: 1) }.frame(width: 20)
                    .disabled(state.playbackRate >= 2)
            }
            .help("Velocidade (0,5× a 2×). Clique no valor para voltar a 1×.")
            // Lado: L = música inteira na esquerda, • = normal, R = inteira na direita.
            Picker("Lado", selection: $state.side) {
                Text("L").tag(-1)
                Image(systemName: "circle.fill").font(.system(size: 5)).tag(0)
                Text("R").tag(1)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .controlSize(.mini)
            .frame(width: 76)
            .help("Som: L (tudo na esquerda), normal ou R (tudo na direita)")
        }
    }

    static func rateText(_ rate: Double) -> String {
        let text = rate == rate.rounded() ? String(format: "%.0f×", rate) : String(format: "%.2f×", rate)
        return text.replacingOccurrences(of: ".", with: ",")
    }
}

/// Medidor ao vivo isolado: observa o MeterModel (30 Hz) sem redesenhar o painel inteiro.
private struct LiveMeter: View {
    @ObservedObject var meter: MeterModel
    let tap: LevelTap

    var body: some View {
        LevelMeter(levels: meter.levels)
            .onAppear { meter.start(tap: tap) }
            .onDisappear { meter.stop() }
    }
}
