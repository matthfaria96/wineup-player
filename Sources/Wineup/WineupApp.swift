import AppKit
import SwiftUI
import WineupCore

@main
struct WineupApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var state = PlayerState()
    @AppStorage("layoutMode.v2") private var layoutRaw = LayoutMode.standard.rawValue
    @AppStorage("themeID") private var themeID = Theme.graphite.id
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        // Uma janela principal: sem restauração da sessão anterior, sem "Nova janela" e arquivos abertos
        // pelo Finder vão para a janela existente (não criam outra). Clique no Dock com ela fechada abre uma.
        WindowGroup("Wineup Player", id: "main") {
            MainView(state: state, layoutRaw: $layoutRaw, themeID: $themeID)
                .onAppear {
                    appDelegate.onOpen = { [weak state] urls in state?.load(urls: urls) }
                    appDelegate.reopenMain = { [openWindow] in openWindow(id: "main") }
                    ClassicKeys.install(state: state)
                }
                .task { await state.startLibrary() }
        }
        .handlesExternalEvents(matching: [])
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
                Button("Importar playlist M3U…") { state.importM3U() }
                Button("Exportar lista como M3U…") { state.exportM3U() }
                Divider()
                Button("Exportar perfil…") { ProfileManager.export(state: state) }
                Button("Importar perfil…") { ProfileManager.importProfile(state: state) }
            }
            CommandMenu("Ir") {
                Button("Voltar") { state.browser.goBack() }.keyboardShortcut("[")
                Button("Avançar") { state.browser.goForward() }.keyboardShortcut("]")
                Button("Subir um nível") { state.browser.goUp() }.keyboardShortcut(.upArrow)
                Divider()
                Button("Pasta padrão") { state.browser.go(folder: state.browser.defaultFolder) }.keyboardShortcut("h", modifiers: [.command, .shift])
                Button("Música") { state.browser.go(folder: NavPlaces.music) }.keyboardShortcut("m", modifiers: [.command, .shift])
                Button("Downloads") { state.browser.go(folder: NavPlaces.downloads) }.keyboardShortcut("l", modifiers: [.command, .option])
                Button("Escolher pasta padrão…") { state.askDefaultFolder() }
                Button("Ir para a pasta…") { state.browser.goToTypedPath() }.keyboardShortcut("g", modifiers: [.command, .shift])
                Divider()
                Button("Copiar caminho da pasta") {
                    PathActions.copy(state.browser.folder)
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
                Divider()
                Button("Mais rápido") { state.changeRate(by: 5) }.keyboardShortcut("=", modifiers: [.command, .option])
                Button("Mais devagar") { state.changeRate(by: -5) }.keyboardShortcut("-", modifiers: [.command, .option])
                Button("Velocidade normal") { state.setRate(1) }.keyboardShortcut("0", modifiers: [.command, .option])
                Divider()
                // Atalhos de uma tecla (janela principal, fora de campos de texto); só informativos aqui.
                Section("Atalhos clássicos") {
                    Button("Z anterior · X tocar · C pausar · V parar · B próxima") {}.disabled(true)
                    Button("← → 5 segundos · ↑ ↓ volume · espaço tocar/pausar") {}.disabled(true)
                }
            }
            CommandMenu("Exibição") {
                Button("Tocar pela barra de menus") { TrayMode.enter(state: state, openWindow: openWindow) }
                .keyboardShortcut("m", modifiers: [.command, .option])
                Divider()
                Picker("Ver pasta por", selection: Binding(get: { state.browser.view }, set: { state.browser.setView($0) })) {
                    ForEach(ViewMode.allCases) { Text($0.title).tag($0) }
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

        Window("Metadados", id: "metadata") {
            MetadataManagerView(state: state)
                .preferredColorScheme(.dark)
        }
        .defaultSize(width: 1240, height: 760)
        .handlesExternalEvents(matching: [])

        Window("Sobre o Wineup Player", id: "about") {
            AboutView()
        }
        .windowResizability(.contentSize)
        .windowStyle(.hiddenTitleBar)
        .handlesExternalEvents(matching: [])
    }
}

/// Comportamento de app comum: nada de reabrir as janelas da última sessão (Metadados, Sobre,
/// cópias da principal). O que volta é a lista que estava tocando, guardada pela própria sessão do app.
/// Arquivos abertos pelo Finder ou arrastados no Dock entram na janela que já existe.
final class AppDelegate: NSObject, NSApplicationDelegate {
    var onOpen: (([URL]) -> Void)? {
        didSet {
            guard let onOpen, !pending.isEmpty else { return }
            onOpen(pending)
            pending = []
        }
    }
    private var pending: [URL] = []
    /// Abre a janela principal (clique no Dock ou arquivo chegando com ela fechada).
    var reopenMain: (() -> Void)?

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { reopenMain?() }
        return false
    }

    func applicationWillFinishLaunching(_ notification: Notification) {
        UserDefaults.standard.set(false, forKey: "NSQuitAlwaysKeepsWindows")
        Self.removeStaleWindowFrames()
        // Nenhuma janela entra no estado que o macOS/SwiftUI reabre na próxima vez.
        NotificationCenter.default.addObserver(forName: NSWindow.didBecomeKeyNotification, object: nil, queue: .main) { note in
            (note.object as? NSWindow)?.isRestorable = false
        }
    }

    /// Se o sistema ainda reabrir Metadados ou Sobre da sessão anterior, fecha: só a principal abre sozinha.
    func applicationDidFinishLaunching(_ notification: Notification) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            for window in NSApp.windows {
                window.isRestorable = false
                let id = window.identifier?.rawValue ?? ""
                if id.hasPrefix("metadata") || id.hasPrefix("about") { window.close() }
            }
        }
    }

    func application(_ app: NSApplication, shouldRestoreSecureApplicationState coder: NSCoder) -> Bool { false }
    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }

    func application(_ application: NSApplication, open urls: [URL]) {
        if NSApp.windows.allSatisfy({ !$0.isVisible }) { reopenMain?() }
        if let onOpen { onOpen(urls) } else { pending += urls }
    }

    /// Molduras salvas das antigas janelas múltiplas (WindowGroup) que não servem mais.
    private static func removeStaleWindowFrames() {
        let defaults = UserDefaults.standard
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix("NSWindow Frame SwiftUI.WindowGroup") {
            defaults.removeObject(forKey: key)
        }
    }
}
