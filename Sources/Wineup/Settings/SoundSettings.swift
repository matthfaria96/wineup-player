import SwiftUI
import WineupCore

/// Aba Som: Correção de Som, equalizador e ReplayGain (os mesmos controles do painel FX).
struct SoundSettings: View {
    @ObservedObject var state: PlayerState
    /// O progresso da medição é publicado à parte do PlayerState.
    @ObservedObject private var status: StatusModel

    init(state: PlayerState) {
        self.state = state
        status = state.status
    }

    var body: some View {
        SettingsPage {
            SettingsSection(title: "Correção de Som",
                            footer: "O Wineup mede o volume percebido de cada música (padrão EBU R128, o mesmo do Spotify e do YouTube) e ajusta na hora de tocar. Os arquivos nunca são alterados; cada música é medida uma vez só.") {
                SettingsRow(title: "Deixar todas no mesmo volume",
                            detail: "Abaixa as músicas altas e sobe as baixas (⌥⌘L).", symbol: "dial.medium") {
                    Toggle("Correção de Som", isOn: $state.soundCorrection).settingsSwitch()
                }
                SettingsSeparator()
                SettingsRow(title: "Nível", detail: "Baixo é mais suave; Alto deixa tudo mais forte.", symbol: "speaker.wave.2") {
                    Picker("Nível", selection: $state.correctionTarget) {
                        ForEach(PlayerState.correctionLevels, id: \.lufs) { level in
                            Text("\(level.name) (\(Int(level.lufs)) LUFS)").tag(level.lufs)
                        }
                    }
                    .settingsMenu()
                    .disabled(!state.soundCorrection)
                }
                SettingsSeparator()
                SettingsRow(title: "Medir agora", detail: measureDetail, symbol: "waveform.badge.magnifyingglass") {
                    Button("Medir a lista") { state.measureLoudness(of: state.tracks) }
                        .disabled(state.loudnessProgress != nil || state.tracks.isEmpty)
                }
            }

            SettingsSection(title: "Equalizador",
                            footer: "O equalizador é o da própria Apple (Core Audio). Presets mudam o timbre ao seu gosto; não consertam a música.") {
                SettingsRow(title: "Preset", detail: EqPreset.builtInDetails[state.preset].map { LocalizedStringKey($0) } ?? "Ajuste feito à mão ou salvo por você.",
                            symbol: "slider.vertical.3") {
                    Picker("Preset", selection: Binding(get: { state.preset }, set: { state.apply(preset: $0) })) {
                        ForEach(state.presets.map(\.name) + (state.presets.contains { $0.name == state.preset } ? [] : [state.preset]),
                                id: \.self) { Text($0).tag($0) }
                    }
                    .settingsMenu()
                }
                SettingsSeparator()
                SettingsRow(title: "Bypass", detail: "Desliga o equalizador sem perder o ajuste.", symbol: "power") {
                    Toggle("Bypass", isOn: $state.eqBypass).settingsSwitch()
                }
                SettingsSeparator()
                SettingsRow(title: "Evitar distorção",
                            detail: "Limitador de pico: segura só o que estouraria, sem baixar o resto da música.",
                            symbol: "waveform.path") {
                    Toggle("Evitar distorção", isOn: $state.preventClipping).settingsSwitch()
                }
            }

            SettingsSection(title: "ReplayGain",
                            footer: "Usa o ganho gravado nas tags por outros programas. Fica desligado enquanto a Correção de Som estiver ligada.") {
                SettingsRow(title: "ReplayGain das tags", symbol: "tag") {
                    Picker("ReplayGain", selection: $state.replayGainMode) {
                        Text("Desligado").tag(ReplayGainMode.off)
                        Text("Por faixa").tag(ReplayGainMode.track)
                        Text("Por álbum").tag(ReplayGainMode.album)
                    }
                    .settingsMenu()
                    .disabled(state.soundCorrection)
                }
            }
        }
    }

    private var measureDetail: LocalizedStringKey {
        if let progress = state.loudnessProgress { return "Medindo \(progress.done) de \(progress.total)…" }
        return "Mede o volume das músicas da lista atual de uma vez."
    }
}
