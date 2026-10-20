import SwiftUI

@main
struct WineupApp: App {
    @StateObject private var state = PlayerState()
    @AppStorage("layoutMode") private var layoutRaw = LayoutMode.grid.rawValue
    @AppStorage("themeID") private var themeID = Theme.graphite.id
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        WindowGroup("Wineup Player") {
            MainView(state: state, layoutRaw: $layoutRaw, themeID: $themeID)
                .onOpenURL { state.load(urls: [$0]) }
                .task { await state.startLibrary() }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1180, height: 720)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("Sobre o Wineup Player") { openWindow(id: "about") }
            }
            CommandGroup(replacing: .newItem) {
                Button("Abrir…") { state.presentOpenPanel() }
                    .keyboardShortcut("o")
            }
            CommandMenu("Exibição") {
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
