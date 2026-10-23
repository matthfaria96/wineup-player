import SwiftUI

/// Botão de velocidade: mostra a taxa atual; ao clicar abre o menu de velocidade.
struct SpeedButton: View {
    @ObservedObject var state: PlayerState
    @Environment(\.theme) private var theme
    @State private var open = false

    var body: some View {
        Button { open.toggle() } label: {
            Text(PlayerPanel.rateText(state.playbackRate))
                .font(.system(size: 10, weight: .semibold)).monospacedDigit()
                .foregroundStyle(abs(state.playbackRate - 1) < 0.001 ? theme.mutedText : theme.accent)
                .padding(.horizontal, 6)
                .frame(height: 18)
                .background(RoundedRectangle(cornerRadius: 5).fill(Color.white.opacity(open ? 0.14 : 0.06)))
                .overlay(RoundedRectangle(cornerRadius: 5).stroke(theme.panelBorder, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .help("Velocidade da reprodução")
        .accessibilityLabel("Velocidade da reprodução")
        .accessibilityValue(PlayerPanel.rateText(state.playbackRate))
        .popover(isPresented: $open, arrowEdge: .bottom) { SpeedMenu(state: state) }
    }
}

/// Menu de velocidade (referência: o do YouTube): valor grande, slider com − e +, atalhos.
struct SpeedMenu: View {
    @ObservedObject var state: PlayerState

    var body: some View {
        VStack(spacing: 14) {
            Text("Velocidade da reprodução")
                .font(.system(size: 13, weight: .semibold))
                .frame(maxWidth: .infinity, alignment: .leading)
            Divider()
            Text(String(format: "%.2fx", state.playbackRate))
                .font(.system(size: 22, weight: .bold)).monospacedDigit()
            HStack(spacing: 10) {
                roundButton("minus") { state.changeRate(by: -1) }
                    .disabled(state.playbackRate <= PlayerState.rateRange.lowerBound)
                Slider(value: Binding(get: { state.playbackRate }, set: { state.setRate($0) }),
                       in: PlayerState.rateRange)
                    .accessibilityLabel("Velocidade")
                roundButton("plus") { state.changeRate(by: 1) }
                    .disabled(state.playbackRate >= PlayerState.rateRange.upperBound)
            }
            HStack(alignment: .top, spacing: 8) {
                ForEach(PlayerState.ratePresets, id: \.self) { rate in
                    VStack(spacing: 4) {
                        Button { state.setRate(rate) } label: {
                            Text(Self.presetText(rate))
                                .font(.system(size: 12, weight: .medium)).monospacedDigit()
                                .frame(minWidth: 40)
                                .padding(.vertical, 6)
                                .background(Capsule().fill(abs(state.playbackRate - rate) < 0.001
                                                           ? Color.accentColor.opacity(0.35) : Color.white.opacity(0.1)))
                        }
                        .buttonStyle(.plain)
                        Text(rate == 1 ? "Normal" : " ").font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(16)
        .frame(width: 340)
    }

    /// 1 → "1,0", 1.5 → "1,5", 1.25 → "1,25".
    static func presetText(_ rate: Double) -> String {
        let hundredths = Int((rate * 100).rounded())
        let text = hundredths % 10 == 0 ? String(format: "%.1f", rate) : String(format: "%.2f", rate)
        return text.replacingOccurrences(of: ".", with: ",")
    }

    private func roundButton(_ symbol: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 12, weight: .bold))
                .frame(width: 28, height: 28)
                .background(Circle().fill(Color.white.opacity(0.1)))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(symbol == "minus" ? "Mais devagar" : "Mais rápido")
    }
}
