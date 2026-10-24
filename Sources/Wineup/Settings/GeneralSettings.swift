import SwiftUI
import WineupLibrary

/// Aba Geral: layout, tema, o que aparece no quadro da capa e atalhos para as outras telas.
struct GeneralSettings: View {
    @ObservedObject var state: PlayerState
    @Binding var layoutRaw: String
    @Binding var themeID: String
    @AppStorage(VisualMode.key) private var modeRaw = VisualMode.firstUse.rawValue
    @AppStorage(VideoCategoryStore.selectedKey) private var videoCategory = ""
    @AppStorage(MotionChoice.key) private var motion = MotionChoice.firstUse
    @ObservedObject private var skins = SkinStore.shared
    @Environment(\.openWindow) private var openWindow
    @State private var showMotion = false
    @State private var language = AppLanguage.current
    /// Idioma ao abrir os Ajustes: se mudar, o app precisa abrir de novo.
    @State private var openedLanguage = AppLanguage.current

    /// As três escolhas do quadro: capa, arte do skin ou vídeos personalizados (animação ou categoria).
    private enum Frame: String { case cover, skinArt, motion }

    private var frame: Binding<String> {
        Binding(
            get: {
                switch VisualMode(rawValue: modeRaw) ?? .firstUse {
                case .cover: Frame.cover.rawValue
                case .skinArt: Frame.skinArt.rawValue
                default: Frame.motion.rawValue
                }
            },
            set: { raw in
                switch Frame(rawValue: raw) {
                case .cover: modeRaw = VisualMode.cover.rawValue
                case .skinArt: modeRaw = VisualMode.skinArt.rawValue
                case .motion: applyMotion()
                case nil: break
                }
            }
        )
    }

    var body: some View {
        SettingsPage {
            SettingsSection(title: "Idioma",
                            footer: language == openedLanguage ? "Sistema usa o idioma do macOS." : "O novo idioma vale quando o Wineup abrir de novo.") {
                SettingsRow(title: "Idioma do app", detail: nil, symbol: "globe") {
                    Picker("Idioma", selection: $language) {
                        Text("Sistema").tag(AppLanguage.system)
                        Divider()
                        ForEach(AppLanguage.supported, id: \.code) { Text(verbatim: $0.name).tag($0.code) }
                    }
                    .settingsMenu()
                    .onChange(of: language) { _, code in AppLanguage.set(code) }
                }
                if language != openedLanguage {
                    SettingsSeparator()
                    SettingsRow(title: "Reabrir o Wineup agora", detail: "A música para e volta ao abrir.", symbol: "arrow.clockwise") {
                        Button("Reabrir") { AppLanguage.relaunch() }
                    }
                }
            }

            SettingsSection(title: "Janela",
                            footer: "Arraste o título de um painel na janela principal para trocá-lo de lugar.") {
                SettingsRow(title: "Layout", detail: LocalizedStringKey(LayoutMode.named(layoutRaw).detail), symbol: "square.grid.2x2") {
                    Picker("Layout", selection: $layoutRaw) {
                        ForEach(LayoutMode.allCases) { Text($0.name).tag($0.rawValue) }
                    }
                    .settingsMenu()
                }
                SettingsSeparator()
                SettingsRow(title: "Tema (skin)", detail: "Cores, molduras, botões e arte de fundo da janela.",
                            symbol: "swatchpalette") {
                    Picker("Tema", selection: $themeID) {
                        Text("Sem skin").tag(Theme.noneID)
                        Divider()
                        ForEach(Theme.all) { Text($0.name).tag($0.id) }
                    }
                    .settingsMenu()
                }
                SettingsSeparator()
                SettingsRow(title: "Editar temas", detail: "Criar, editar, importar ou exportar skins.", symbol: "paintbrush") {
                    Button("Abrir…") { openWindow(id: "themes") }
                }
            }

            SettingsSection(title: "Quadro da capa",
                            footer: "Sem capa na música, o quadro mostra a arte do skin. O botão no canto do quadro faz a mesma escolha.") {
                SettingsRow(title: "Mostrar", detail: frameDetail, symbol: "photo") {
                    Picker("Mostrar", selection: frame) {
                        Text("Capa da música").tag(Frame.cover.rawValue)
                        Text("Arte do skin").tag(Frame.skinArt.rawValue)
                        Text("Vídeos personalizados").tag(Frame.motion.rawValue)
                    }
                    .settingsMenu()
                }
                SettingsSeparator()
                SettingsRow(title: "Vídeos personalizados", detail: MotionChoice.label(motion).map { LocalizedStringKey($0) } ?? "Nenhum escolhido",
                            symbol: "film") {
                    Button("Escolher…") { showMotion = true }
                }
            }

            SettingsSection(title: "Outras telas") {
                SettingsRow(title: "Metadados", detail: "Tags, capas e letras das músicas.", symbol: "tag") {
                    Button("Abrir") { openWindow(id: "metadata") }
                }
                SettingsSeparator()
                SettingsRow(title: "Tocar pela barra de menus",
                            detail: "Fecha a janela e deixa um player pequeno no topo do Mac (⌥⌘M).",
                            symbol: "menubar.arrow.up.rectangle") {
                    Button("Ir") { TrayMode.enter(state: state, openWindow: openWindow) }
                }
            }
        }
        .sheet(isPresented: $showMotion) { MotionLibraryView(modeRaw: $modeRaw, videoCategory: $videoCategory) }
    }

    private var frameDetail: LocalizedStringKey {
        switch Frame(rawValue: frame.wrappedValue) {
        case .cover: "A capa da música que está tocando."
        case .skinArt: "A ilustração do skin em uso."
        default: MotionChoice.label(motion).map { "Agora: \($0)." } ?? "Escolha uma animação ou vídeo."
        }
    }

    /// Mesma regra do botão do quadro: usa a animação ou categoria escolhida; sem nenhuma, abre a escolha.
    private func applyMotion() {
        if motion.hasPrefix("scene:") { modeRaw = String(motion.dropFirst(6)) }
        else if motion.hasPrefix("video:") { videoCategory = String(motion.dropFirst(6)); modeRaw = VisualMode.videos.rawValue }
        else { showMotion = true }
    }
}
