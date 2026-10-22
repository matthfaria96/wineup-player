import SwiftUI
import WineupCore

@main
struct WineupApp: App {
    @StateObject private var state = PlayerState()
    @AppStorage("layoutMode.v2") private var layoutRaw = LayoutMode.standard.rawValue
    @AppStorage("themeID") private var themeID = Theme.graphite.id
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        WindowGroup("Wineup Player") {
            MainView(state: state, layoutRaw: $layoutRaw, themeID: $themeID)
                .onOpenURL { state.load(urls: [$0]) }
                .task { await state.startLibrary() }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1000, height: 720)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("Sobre o Wineup Player") { openWindow(id: "about") }
            }
            CommandGroup(replacing: .newItem) {
                Button("Abrir…") { state.presentOpenPanel() }
                    .keyboardShortcut("o")
                Button("Nova playlist") { state.newPlaylist(with: nil) }
                    .keyboardShortcut("n")
                Divider()
                Button("Exportar perfil…") { ProfileManager.export(state: state) }
                Button("Importar perfil…") { ProfileManager.importProfile(state: state) }
            }
            CommandMenu("Ir") {
                Button("Voltar") { state.browser.goBack() }.keyboardShortcut("[")
                Button("Avançar") { state.browser.goForward() }.keyboardShortcut("]")
                Button("Subir um nível") { state.browser.goUp() }.keyboardShortcut(.upArrow)
                Divider()
                Button("Música") { state.browser.goFolder(NavPlaces.music) }.keyboardShortcut("m", modifiers: [.command, .shift])
                Button("Downloads") { state.browser.goFolder(NavPlaces.downloads) }.keyboardShortcut("l", modifiers: [.command, .option])
                Button("Biblioteca") { state.browser.goLibrary(.albums) }.keyboardShortcut("b", modifiers: [.command, .shift])
                Button("Ir para a pasta…") { state.browser.goToTypedPath() }.keyboardShortcut("g", modifiers: [.command, .shift])
                Divider()
                Button("Copiar caminho da pasta") {
                    if let url = state.browser.currentFolder { PathActions.copy(url) }
                }
                .keyboardShortcut("c", modifiers: [.command, .option])
                Button("Atualizar") { state.browser.refresh() }.keyboardShortcut("r")
            }
            CommandMenu("Controles") {
                Button("Tocar/Pausar") { state.togglePlay() }.keyboardShortcut(.space, modifiers: [.command])
                Button("Tocar faixa selecionada") { state.playSelected() }.keyboardShortcut(.return, modifiers: [.command])
                Button("Remover faixa selecionada") { state.removeSelected() }.keyboardShortcut(.delete, modifiers: [.command])
                Divider()
                Toggle("Aleatório", isOn: Binding(get: { state.shuffleOn }, set: { state.shuffleOn = $0 }))
                Picker("Repetir", selection: Binding(get: { state.repeatMode }, set: { state.repeatMode = $0 })) {
                    Text("Desligado").tag(RepeatMode.off)
                    Text("Todas").tag(RepeatMode.all)
                    Text("Uma").tag(RepeatMode.one)
                }
                Divider()
                Button("Próxima") { state.step(by: 1) }.keyboardShortcut(.rightArrow, modifiers: [.command, .option])
                Button("Anterior") { state.step(by: -1) }.keyboardShortcut(.leftArrow, modifiers: [.command, .option])
                Button("Parar") { state.stop() }.keyboardShortcut(".")
                Button("Faixa aleatória") { state.playRandom() }.keyboardShortcut("s", modifiers: [.command, .option])
            }
            CommandMenu("Exibição") {
                Picker("Ver biblioteca por", selection: Binding(get: { state.browser.mode }, set: { state.browser.mode = $0 })) {
                    ForEach(BrowseMode.allCases) { Text($0.title).tag($0) }
                }
                Picker("Estilo da lista", selection: Binding(get: { state.listStyle }, set: { state.listStyle = $0 })) {
                    ForEach(ListStyle.allCases) { Text($0.title).tag($0) }
                }
                Toggle("Mostrar playlists de tags", isOn: Binding(get: { state.browser.showColorTags },
                                                                set: { state.browser.showColorTags = $0 }))
                Divider()
                ForEach(Array(LayoutMode.allCases.enumerated()), id: \.element.id) { index, mode in
                    Button(mode.name) { layoutRaw = mode.rawValue }
                        .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .command)
                }
                Divider()
                ForEach(Array(Theme.all.enumerated()), id: \.element.id) { index, theme in
                    Button("Tema \(theme.name)") { themeID = theme.id }
                        .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: [.command, .option])
                }
            }
        }

        Window("Sobre o Wineup Player", id: "about") {
            AboutView()
        }
        .windowResizability(.contentSize)
        .windowStyle(.hiddenTitleBar)
    }
}
