import WineupAudio
import WineupCore
import Combine
import WineupCore
import SwiftUI

struct PlayerPanel: View {
    @ObservedObject var state: PlayerState

    @Environment(\.theme) private var theme

    var body: some View {
        Panel(title: "Player") {
            VStack(alignment: .leading, spacing: 8) {
                header
                readout
                ClockedWaveform(state: state, clock: state.clock)
                    .frame(height: 26)
                    .opacity(state.currentTrack == nil ? 0.2 : 1)
                    .allowsHitTesting(state.currentTrack != nil)
                    .hint("Forma de onda", "O volume da música do começo ao fim: trechos altos ficam altos. Clique para pular para esse ponto.")
                transport
                mixRow
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 10)
        }
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
            .foregroundStyle(theme.display.opacity(0.6))
            // Barras e tempo restante com a mesma altura: topo e base na mesma linha.
            HStack(alignment: .center, spacing: 10) {
                LiveMeter(meter: state.meterModel, tap: state.meter)
                    .frame(maxWidth: .infinity, alignment: .leading)
                RemainingTime(state: state, clock: state.clock)
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
                .hint("Anterior (Z)", "Volta para a música anterior da lista.")
            ChromeButton(symbol: state.isPlaying ? "pause.fill" : "play.fill", isOn: state.isPlaying) { state.togglePlay() }
                .frame(width: 48)
                .hint(state.isPlaying ? "Pausar (espaço)" : "Tocar (espaço)", "Toca ou pausa a música atual.")
            ChromeButton(symbol: "stop.fill") { state.stop() }.frame(width: 38)
                .hint("Parar (V)", "Para a música e volta ao começo dela.")
            ChromeButton(symbol: "forward.fill") { state.step(by: 1) }.frame(width: 38)
                .hint("Próxima (B)", "Pula para a próxima música da lista.")
            Spacer(minLength: 0)
            ChromeButton(symbol: "shuffle", isOn: state.shuffleOn) { state.shuffleOn.toggle() }
                .frame(width: 34)
                .hint(state.shuffleOn ? "Aleatório: ligado" : "Aleatório: desligado", "Toca as músicas da lista fora de ordem.")
            ChromeButton(symbol: state.repeatMode == .one ? "repeat.1" : "repeat", isOn: state.repeatMode != .off) {
                state.repeatMode = { switch state.repeatMode { case .off: .all; case .all: .one; case .one: .off } }()
            }
            .frame(width: 34)
            .hint(["off": "Repetir: desligado", "all": "Repetir: todas", "one": "Repetir: uma"][state.repeatMode.rawValue] ?? "Repetir",
                  "Clique para alternar: não repetir, repetir a lista toda ou repetir só esta música.")
            ChromeButton(symbol: "folder") { state.presentOpenPanel() }.frame(width: 34)
                .hint("Abrir (⌘O)", "Abre arquivos de música ou pastas inteiras para tocar.")
        }
    }

    private var mixRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "speaker.wave.2.fill").font(.system(size: 10)).foregroundStyle(theme.mutedText)
            VolumeSlider(mixer: state.mixer).frame(height: 16)
                .accessibilityLabel("Volume")
                .hint("Volume (↑ ↓)", "Volume do Wineup. Não muda o volume do Mac.")
            // Velocidade: botão com o valor; o menu (como o do YouTube) tem slider, − / + e atalhos.
            SpeedButton(state: state)
            // Lado: L = música inteira na esquerda, • = normal, R = inteira na direita.
            SkinSegmented(selection: $state.side, options: [-1, 0, 1], width: 12) { side in
                Group {
                    if side == 0 { Image(systemName: "circle.fill").font(.system(size: 5)) }
                    else { Text(side < 0 ? "L" : "R").font(.system(size: 10, weight: .bold)) }
                }
                .accessibilityLabel(side < 0 ? "Esquerda" : side > 0 ? "Direita" : "Normal")
            }
            .frame(height: 18)
            .hint("Lado do som", "L: a música inteira no fone/caixa da esquerda. •: normal (estéreo). R: inteira na direita.")
        }
    }

    static func rateText(_ rate: Double) -> String {
        String(format: "%.2f×", rate).replacingOccurrences(of: ".", with: ",")
    }
}

/// Medidor ao vivo isolado: observa o MeterModel (30 Hz) sem redesenhar o painel inteiro.
private struct LiveMeter: View {
    @ObservedObject var meter: MeterModel
    let tap: LevelTap

    var body: some View {
        LevelMeter(levels: meter.bars)
            .accessibilityHidden(true)
            .hint("Medidor de volume", "Canal esquerdo em cima e direito embaixo. Acende conforme a música: amarelo nos trechos fortes, vermelho nos picos.")
            .onAppear { meter.attach(tap: tap) }
            .onDisappear { meter.detach() }
    }
}

/// Forma de onda: só ela redesenha a cada passo do relógio (e não o painel inteiro).
private struct ClockedWaveform: View {
    let state: PlayerState
    @ObservedObject var clock: PlaybackClock

    var body: some View {
        WaveformView(url: state.currentTrack?.url, progress: clock.progress, onSeek: state.seek(to:))
    }
}

/// Tempo restante no visor, isolado pelo mesmo motivo.
private struct RemainingTime: View {
    let state: PlayerState
    @ObservedObject var clock: PlaybackClock

    var body: some View {
        SevenSegmentText(text: PlayerPanel.lcdTime(state.remainingSeconds), digitHeight: LevelMeter.totalHeight)
    }
}

/// Volume: o arrasto redesenha só o slider.
private struct VolumeSlider: View {
    @ObservedObject var mixer: MixerModel

    var body: some View {
        ChromeSlider(value: $mixer.volume, knobThickness: 12)
    }
}
