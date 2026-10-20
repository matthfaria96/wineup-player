import SwiftUI
import WineupCore

struct EqualizerPanel: View {
    @ObservedObject var state: PlayerState

    @Environment(\.theme) private var theme
    @StateObject private var dialogs = PresetDialogs()
    private let labels = ["60", "170", "310", "600", "1K", "2K", "5K", "8K", "12K", "16K"]

    var body: some View {
        Panel(title: "FX") {
            VStack(spacing: 8) {
                controls
                presetBar
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
            ChromeButton(isOn: state.eqBypass, action: { state.eqBypass.toggle() }) {
                HStack(spacing: 4) {
                    Text("Bypass")
                    RoundedRectangle(cornerRadius: 2)
                        .fill(state.eqBypass ? theme.text : theme.mutedText.opacity(0.4))
                        .frame(width: 8, height: 8)
                }
            }
            .frame(width: 84)
            Picker("", selection: Binding(get: { state.preset }, set: { state.apply(preset: $0) })) {
                ForEach((state.presets.map(\.name) + ["Custom"]), id: \.self) { Text($0).tag($0) }
            }
            .labelsHidden()
            .frame(maxWidth: .infinity)
            ChromeButton("Reset") { state.apply(preset: "Flat"); state.preamp = 0 }
                .frame(width: 58)
        }
    }

    private var presetBar: some View {
        HStack(spacing: 6) {
            ChromeButton("Salvar") { dialogs.nameInput = ""; dialogs.showSave = true }.frame(width: 60)
            ChromeButton("Renomear") { dialogs.nameInput = state.preset; dialogs.showRename = true }
                .frame(width: 76).disabled(!state.isUserPreset)
            ChromeButton("Apagar") { dialogs.showDelete = true }.frame(width: 60).disabled(!state.isUserPreset)
            Spacer(minLength: 0)
            Picker("ReplayGain", selection: $state.replayGainMode) {
                Text("RG: Desligado").tag(ReplayGainMode.off)
                Text("RG: Faixa").tag(ReplayGainMode.track)
                Text("RG: Álbum").tag(ReplayGainMode.album)
            }
            .labelsHidden()
            .frame(width: 120)
            Toggle("Evitar clipping", isOn: $state.preventClipping)
                .toggleStyle(.checkbox)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(theme.text)
        }
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
            column(value: $state.preamp, label: "Pre")
            ForEach(Array(labels.enumerated()), id: \.offset) { index, label in
                column(value: bandBinding(index), label: label)
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
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(theme.text)
                .frame(height: 12)
        }
        .frame(maxWidth: .infinity)
    }

    private func bandBinding(_ index: Int) -> Binding<Double> {
        Binding(
            get: { state.bands.indices.contains(index) ? state.bands[index] : 0 },
            set: { newValue in
                state.bands = state.bands.enumerated().map { $0.offset == index ? newValue : $0.element }
                state.preset = "Custom"
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
