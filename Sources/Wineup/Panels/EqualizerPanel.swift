import SwiftUI
import WineupCore

struct EqualizerPanel: View {
    @ObservedObject var state: PlayerState
    /// Pre e faixas: arrastar redesenha só este painel.
    @ObservedObject private var mixer: MixerModel

    init(state: PlayerState) {
        self.state = state
        mixer = state.mixer
    }

    @Environment(\.theme) private var theme
    @StateObject private var dialogs = PresetDialogs()
    @State private var showPresets = false
    private let labels = ["60", "170", "310", "600", "1K", "2K", "5K", "8K", "12K", "16K"]
    /// O que cada faixa de frequência muda no som (dica ao passar o mouse).
    private let bandHints = [
        "Subgrave: o peso da batida e do bumbo.",
        "Grave: o corpo do baixo.",
        "Grave-médio: calor. Demais deixa o som embolado.",
        "Médio-grave: o corpo das vozes e dos violões.",
        "Médio: a presença da voz e da caixa da bateria.",
        "Médio-agudo: ataque e clareza. Demais cansa o ouvido.",
        "Presença: a nitidez da voz e das consoantes.",
        "Agudo: o brilho dos pratos.",
        "Brilho: detalhe e ar.",
        "Ar: o brilho mais alto, bem sutil.",
    ]

    var body: some View {
        Panel(title: "FX") {
            VStack(spacing: 8) {
                controls
                sliders
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 10)
        }
    }

    private var controls: some View {
        HStack(spacing: 8) {
            Text("+12dB")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(theme.text)
                .hint("Escala do equalizador", "Cada controle sobe ou desce até 12 dB. A linha pontilhada é o 0 (sem mudança).")
            ChromeButton(isOn: state.eqBypass, action: { state.eqBypass.toggle() }) {
                HStack(spacing: 4) {
                    Text("Bypass")
                    RoundedRectangle(cornerRadius: 2)
                        .fill(state.eqBypass ? theme.text : theme.mutedText.opacity(0.4))
                        .frame(width: 8, height: 8)
                }
            }
            .frame(width: 74)
            .hint(state.eqBypass ? "Bypass ligado" : "Bypass",
                  "Desliga o equalizador para comparar com o som original, sem perder o seu ajuste.")
            ChromeButton(isOn: state.soundCorrection, spoken: "Correção de Som",
                         action: { state.soundCorrection.toggle() }) {
                Image(systemName: "dial.medium")
            }
            .frame(width: 30)
            .hint(state.soundCorrection ? "Correção de Som: ligada" : "Correção de Som: desligada",
                  "Deixa todas as músicas no mesmo volume: abaixa as altas e sobe as baixas. Não altera os arquivos. Nível e medição no menu ⋯ ao lado.")
            // Botão + lista própria (e não um Menu do sistema): o nome longo vira "…" e o botão
            // nunca cresce nem empurra os outros controles do FX.
            Button { showPresets.toggle() } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold)).opacity(0.8)
                    Text(state.preset).lineLimit(1).truncationMode(.tail)
                    Spacer(minLength: 0)
                }
                .frame(minWidth: 0, maxWidth: .infinity)
            }
            .buttonStyle(SkinButtonStyle(compact: true))
            .frame(minWidth: 0, maxWidth: .infinity)
            .layoutPriority(-1)
            .popover(isPresented: $showPresets, arrowEdge: .bottom) {
                PresetList(state: state) { showPresets = false }
            }
            .hint("Preset: \(state.preset)", presetHint)
            ChromeButton("Reset") { withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { state.apply(preset: "Flat"); state.preamp = 0 } }
                .frame(width: 48)
                .hint("Reset", "Volta todas as faixas e o Pre para 0 (Flat).")
            presetBar
                .hint("Mais opções", "Salvar e apagar presets, nível da Correção de Som, medir o volume das músicas e ReplayGain.")
        }
    }

    private var presetHint: String {
        let what = EqPreset.builtInDetails[state.preset] ?? (state.isUserPreset ? "Preset salvo por você." : "Ajuste feito à mão.")
        return what + " Presets mudam o timbre ao seu gosto; não consertam a música."
    }

    /// Presets e ReplayGain num menu compacto, para não apertar os sliders.
    private var presetBar: some View {
        Menu {
            Button("Salvar preset…") { dialogs.nameInput = ""; dialogs.showSave = true }
            Button("Renomear preset…") { dialogs.nameInput = state.preset; dialogs.showRename = true }
                .disabled(!state.isUserPreset)
            Button("Apagar preset") { dialogs.showDelete = true }.disabled(!state.isUserPreset)
            Divider()
            Toggle("Correção de Som", isOn: $state.soundCorrection)
            Picker("Nível da Correção de Som", selection: $state.correctionTarget) {
                ForEach(PlayerState.correctionLevels, id: \.lufs) { level in
                    Text("\(level.name) (\(Int(level.lufs)) LUFS)").tag(level.lufs)
                }
            }
            .disabled(!state.soundCorrection)
            Button("Medir o volume das músicas da lista") { state.measureLoudness(of: state.tracks) }
            Divider()
            Picker("ReplayGain das tags", selection: $state.replayGainMode) {
                Text("Desligado").tag(ReplayGainMode.off)
                Text("Por faixa").tag(ReplayGainMode.track)
                Text("Por álbum").tag(ReplayGainMode.album)
            }
            .disabled(state.soundCorrection)
            Toggle("Evitar distorção (limitador)", isOn: $state.preventClipping)
        } label: {
            Image(systemName: "slider.horizontal.3").foregroundStyle(theme.text)
        }
        .skinMenuChrome(compact: true)
        .alert("Salvar preset", isPresented: $dialogs.showSave) {
            TextField("Nome", text: $dialogs.nameInput)
            Button("Salvar") { state.savePreset(named: dialogs.nameInput) }
            Button("Cancelar", role: .cancel) {}
        }
        .alert("Renomear preset", isPresented: $dialogs.showRename) {
            TextField("Nome", text: $dialogs.nameInput)
            Button("Renomear") { state.renamePreset(state.preset, to: dialogs.nameInput) }
            Button("Cancelar", role: .cancel) {}
        }
        .alert("Apagar preset \"\(state.preset)\"?", isPresented: $dialogs.showDelete) {
            Button("Apagar", role: .destructive) { state.deletePreset(state.preset) }
            Button("Cancelar", role: .cancel) {}
        }
    }

    private var sliders: some View {
        HStack(spacing: 0) {
            column(value: $mixer.preamp, label: "Pre")
                .hint("Pre (pré-amplificação)", "Volume geral antes do equalizador. Abaixe se o som distorcer com muitos reforços.")
            ForEach(Array(labels.enumerated()), id: \.offset) { index, label in
                column(value: bandBinding(index), label: label)
                    .hint(label.hasSuffix("K") ? "\(label.dropLast()) kHz" : "\(label) Hz", bandHints[index])
            }
        }
        .background(alignment: .center) {
            GeometryReader { geo in
                Path { path in
                    path.move(to: CGPoint(x: 0, y: (geo.size.height - 16) / 2))
                    path.addLine(to: CGPoint(x: geo.size.width, y: (geo.size.height - 16) / 2))
                }
                .stroke(theme.mutedText.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [2, 3]))
            }
        }
    }

    private func column(value: Binding<Double>, label: String) -> some View {
        VStack(spacing: 4) {
            ChromeSlider(value: value, range: -12...12, axis: .vertical, knobLength: 9, knobThickness: 18)
                .frame(maxHeight: .infinity)
                .accessibilityLabel(label == "Pre" ? "Pré-amplificação" : "Equalizador \(label) hertz")
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(theme.text)
                .frame(height: 12)
        }
        .frame(maxWidth: .infinity)
    }

    private func bandBinding(_ index: Int) -> Binding<Double> {
        Binding(
            get: { mixer.bands.indices.contains(index) ? mixer.bands[index] : 0 },
            set: { newValue in
                mixer.bands = mixer.bands.enumerated().map { $0.offset == index ? newValue : $0.element }
                // Só publica a troca de preset uma vez (não a cada passo do arrasto).
                if state.preset != "Custom" { state.preset = "Custom" }
            }
        )
    }
}

/// Estado dos diálogos de preset (ObservableObject: o macro @State não está disponível só com CLT).
final class PresetDialogs: ObservableObject {
    @Published var nameInput = ""
    @Published var showSave = false
    @Published var showRename = false
    @Published var showDelete = false
}

/// Lista dos presets com a explicação de cada um; o escolhido tem a marca.
private struct PresetList: View {
    @ObservedObject var state: PlayerState
    let close: () -> Void

    private var names: [String] {
        let all = state.presets.map(\.name)
        return all.contains(state.preset) ? all : all + [state.preset]
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 1) {
                ForEach(names, id: \.self) { name in
                    Button {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { state.apply(preset: name) }
                        close()
                    } label: {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Image(systemName: "checkmark").font(.system(size: 10, weight: .bold))
                                .opacity(name == state.preset ? 1 : 0)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(name).font(.system(size: 12, weight: .medium)).lineLimit(1)
                                Text(EqPreset.builtInDetails[name] ?? (name == "Custom" ? "Ajuste feito à mão." : "Preset salvo por você."))
                                    .font(.system(size: 10.5)).foregroundStyle(.secondary).lineLimit(2)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 8).padding(.vertical, 5)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .background(RoundedRectangle(cornerRadius: 5).fill(name == state.preset ? Color.accentColor.opacity(0.15) : .clear))
                }
            }
            .padding(6)
        }
        .frame(width: 260, height: 360)
    }
}
