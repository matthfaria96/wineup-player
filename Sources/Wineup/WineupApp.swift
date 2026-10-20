import SwiftUI

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
