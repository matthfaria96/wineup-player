import WineupLibrary
import AppKit
import SwiftUI

struct MainView: View {
    /// Não observa o PlayerState: busca, painéis e botões observam só o que desenham.
    let state: PlayerState
    @Binding var layoutRaw: String
    @Binding var themeID: String
    @StateObject private var model = MainViewModel()
    /// Compacto: a busca aberta ocupa a barra do topo inteira (os botões voltam ao fechar).
    @State private var searchExpanded = false
    @AppStorage(WindowVisibility.skinAnimationKey) private var skinAnimation = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.openWindow) private var openWindow
    /// Editar um tema no editor redesenha a janela na hora.
    @ObservedObject private var skins = SkinStore.shared
    /// Janela coberta ou minimizada: as animações do skin e das cenas param.
    @ObservedObject private var visibility = WindowVisibility.shared

    var body: some View {
        let scheme = Theme.colorScheme(themeID: themeID)
        let theme = Theme.named(themeID)
        let layout = LayoutMode.named(layoutRaw)

        VStack(spacing: 6) {
            header(theme: theme, compact: layout == .compact)
            ArrangedLayout(state: state, mode: layout, columns: $model.columns)
                .padding([.horizontal, .bottom], 8)
        }
        .ignoresSafeArea(.container, edges: .top)
        .environment(\.theme, theme)
        .background { ThemeBackground(theme: theme) }
        // Depois do fundo: assim a arte animada da janela também pausa e muda de ritmo.
        .environment(\.animationsPaused, !visibility.mainVisible || (skinAnimation == false) || reduceMotion)
        .environment(\.animationFPS, visibility.animationFPS)
        .frame(minWidth: layout.minSize.width, minHeight: layout.minSize.height)
        .background(WindowAccessor(onWindow: { window in
            let first = model.window == nil
            model.window = window
            WindowVisibility.shared.track(window)
            GlassWindow.apply(window, glass: theme.isGlass)
            // Ao abrir, ninguém fica com o foco (a busca não captura o teclado).
            if first {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    window.makeFirstResponder(nil)
                    searchExpanded = false
                }
            }
        }))
        .onAppear {
            model.columns = layout.columns()
            resizeWindow(for: layout)
            // A janela não abre com o foco na busca (não captura o teclado sozinha).
            DispatchQueue.main.async {
                model.window?.makeFirstResponder(nil)
                searchExpanded = false
            }
        }
        .onChange(of: layoutRaw) { _, raw in
            let mode = LayoutMode.named(raw)
            model.columns = mode.columns()
            resizeWindow(for: mode)
        }
        .preferredColorScheme(scheme)
        .dropDestination(for: URL.self) { urls, _ in
            state.load(urls: urls)
            return true
        }
    }

    /// Barra no nível dos botões da janela: Metadados à esquerda, layout no extremo direito.
    /// Com skin, a barra ganha fundo/moldura do skin e todos os controles usam a arte do skin.
    private func header(theme: Theme, compact: Bool) -> some View {
        HStack(spacing: 0) {
            // Área dos botões fechar/minimizar/maximizar: fica limpa, sobre o fundo da janela (padrão da Apple).
            Color.clear.frame(width: 76)
            headerBar(theme: theme, compact: compact)
        }
        .frame(height: 38)
        .background(DragArea())
    }

    /// A faixa decorada do topo: começa depois dos botões da janela.
    private func headerBar(theme: Theme, compact: Bool) -> some View {
        let searchOnly = compact && searchExpanded
        return HStack(spacing: 8) {
            if !searchOnly { leadingControls(compact: compact) }
            SearchBox(search: state.search, compact: compact, expanded: $searchExpanded)
            if !searchOnly { trailingControls(compact: compact) }
        }
        .font(.system(size: 11))
        .padding(.trailing, 10)
        .frame(height: 34)
        // No Glass, os botões do topo são de vidro (estão sobre o fundo da janela, não num painel).
        .environment(\.onWindowChrome, true)
        .animation(.easeOut(duration: 0.18), value: searchOnly)
        .onChange(of: compact) { _, isCompact in if !isCompact { searchExpanded = false } }
    }

    /// Voltar/Avançar e Metadados; depois deles, o espaço livre do topo (arrasta a janela).
    @ViewBuilder private func leadingControls(compact: Bool) -> some View {
        HistoryButtons(browser: state.browser)
        Button { openWindow(id: "metadata") } label: {
            if compact { Image(systemName: "tag") }
            else { Label("Metadados", systemImage: "tag").labelStyle(.titleAndIcon) }
        }
        .buttonStyle(SkinButtonStyle())
        .hint("Metadados", "Abre o gerenciador de tags: título, artista, álbum, capas e letras das músicas. Busca dados online e salva nos arquivos.")
        Spacer(minLength: 8)
    }

    /// Barra de menus, tema e layout. No Compacto, tudo num único menu (⋯), para sobrar espaço no topo.
    @ViewBuilder private func trailingControls(compact: Bool) -> some View {
        if compact {
            SkinMenu(minWidth: Self.iconButtonWidth - 16) {
                Button("Tocar pela barra de menus") { TrayMode.enter(state: state, openWindow: openWindow) }
                Divider()
                Section("Layout") { layoutPicker }
                Divider()
                Section("Tema") { themeItems }
            } label: {
                Image(systemName: "ellipsis")
            }
            .hint("Mais opções", "Tocar pela barra de menus, layout da janela e tema (Glass, sem skin ou skins personalizados).")
        } else {
            Spacer(minLength: 8)
            Button { TrayMode.enter(state: state, openWindow: openWindow) } label: {
                Image(systemName: "menubar.arrow.up.rectangle").frame(width: Self.iconButtonWidth - 12)
            }
            .buttonStyle(SkinButtonStyle(compact: true))
            .hint("Tocar pela barra de menus (⌥⌘M)", "Fecha a janela e deixa um player pequeno no topo do Mac, ao lado do relógio. A música continua tocando.")
            .accessibilityLabel("Tocar pela barra de menus")
            // Skin: entre a barra de menus e o layout, com a mesma largura do botão da barra de menus.
            SkinMenu(minWidth: Self.iconButtonWidth - 16) { themeItems } label: {
                Image(systemName: "swatchpalette")
            }
            .hint("Tema (skin)", "Troca o visual da janela inteira: Glass (o visual da Apple, padrão), sem skin escuro ou claro, ou um skin personalizado com cores, molduras e arte de fundo. Também dá para editar, criar e importar skins.")
            // Seletor de layout que mostra o modo atual.
            SkinMenu { layoutPicker } label: {
                Label(LayoutMode.named(layoutRaw).name, systemImage: "square.grid.2x2").labelStyle(.titleAndIcon)
            }
            .hint("Layout: \(LayoutMode.named(layoutRaw).name)", "Compacto: só o player e a lista, numa coluna. Padrão: lista, player, FX e capa. Completo: tudo isso e a letra ao lado. Arraste o título de um painel para trocá-lo de lugar.")
        }
    }

    /// Temas: o padrão (Glass), o visual simples escuro/claro e, abaixo, os skins personalizados.
    @ViewBuilder private var themeItems: some View {
        Button { themeID = Theme.glassID } label: {
            Label("Glass (padrão)", systemImage: themeID == Theme.glassID ? "checkmark" : "drop.halffull")
        }
        Divider()
        Section("Sem skin") {
            Button { themeID = Theme.noneID } label: {
                Label("Escuro", systemImage: themeID == Theme.noneID ? "checkmark" : "moon")
            }
            Button { themeID = Theme.noneLightID } label: {
                Label("Claro", systemImage: themeID == Theme.noneLightID ? "checkmark" : "sun.max")
            }
        }
        Divider()
        Section("Skins personalizados") {
            ForEach(Theme.all) { skin in
                Button { themeID = skin.id } label: {
                    Label(skin.name, systemImage: themeID == skin.id ? "checkmark" : "paintpalette")
                }
            }
        }
        Divider()
        Button("Editar, criar, importar ou exportar skins…") { openWindow(id: "themes") }
    }

    private var layoutPicker: some View {
        Picker("Layout", selection: $layoutRaw) {
            ForEach(LayoutMode.allCases) { Text($0.name).tag($0.rawValue) }
        }
        .pickerStyle(.inline)
        .labelsHidden()
    }
}

extension MainView {
    /// Largura total dos botões de ícone do topo: barra de menus e tema ficam do mesmo tamanho
    /// (o botão tem 6 pt de margem de cada lado; o menu do tema, 8 pt).
    static let iconButtonWidth: CGFloat = 42

    /// Ajusta a largura da janela ao modo (o Compacto fica estreito, sem sobras dos lados).
    func resizeWindow(for mode: LayoutMode) {
        DispatchQueue.main.async {
            guard let window = model.window else { return }
            let target: CGFloat
            switch mode {
            case .compact: target = 470
            case .standard: target = max(min(window.frame.width, 1100), 960)
            case .full: target = max(window.frame.width, 1380)
            }
            var frame = window.frame
            let top = frame.maxY
            frame.size.width = target
            // Compacto: alto o bastante para a lista mostrar várias faixas abaixo do player e do FX
            // (sem passar da área útil da tela).
            if mode == .compact {
                let available = window.screen?.visibleFrame.height ?? 980
                frame.size.height = min(max(frame.height, 980), max(available, mode.minSize.height))
            }
            // Padrão e Completo: altura exata da coluna da capa, sem sobras acima e abaixo dela.
            else { frame.size.height = mode.minSize.height }
            frame.origin.y = top - frame.height
            window.setFrame(frame, display: true, animate: true)
        }
    }
}

/// Caixa de busca: observa só a busca (digitar não redesenha a janela inteira).
private struct SearchBox: View {
    @ObservedObject var search: SearchModel
    let compact: Bool
    /// Compacto: aberta, a busca ocupa a barra inteira; o X no fim ou um clique fora fecha.
    @Binding var expanded: Bool
    @Environment(\.theme) private var theme
    /// Foco da busca: clicar na caixa (ou ⌘F) põe o cursor no campo.
    @FocusState private var searchFocused: Bool
    /// Área da caixa na janela e o vigia de cliques fora dela (só com a busca aberta).
    @State private var fieldFrame: CGRect = .zero
    @State private var clickMonitor: Any?

    var body: some View {
        Group {
            // Compacto fechado: só o ícone (o topo fica livre para arrastar a janela).
            if compact && !expanded { iconButton } else { field }
        }
        .background {
            // ⌘F: vai para a busca.
            Button("") { open() }.keyboardShortcut("f", modifiers: .command).opacity(0).allowsHitTesting(false)
        }
        // Com foco, a busca do Compacto abre; sem foco (clique em outro lugar), fecha.
        .onChange(of: searchFocused) { _, focused in
            if compact { expanded = focused }
        }
        .onChange(of: expanded) { _, isOpen in isOpen ? watchClicksOutside() : stopWatching() }
        .onDisappear { stopWatching() }
    }

    /// Ícone da busca no Compacto; aceso quando há uma busca em uso.
    private var iconButton: some View {
        Button { open() } label: {
            Image(systemName: "magnifyingglass").frame(width: MainView.iconButtonWidth - 12)
        }
        .buttonStyle(SkinButtonStyle(on: !search.query.isEmpty, compact: true))
        .hint("Buscar (⌘F)", "Abre a busca na barra do topo: procura músicas por título, artista ou álbum em toda a sua biblioteca. O X ou um clique fora fecha.")
        .accessibilityLabel("Buscar")
    }

    private var field: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").foregroundStyle(theme.mutedText)
            TextField(compact ? "Buscar" : "Buscar em sua biblioteca…", text: $search.query)
                .textFieldStyle(.plain)
                .foregroundStyle(theme.text)
                .focused($searchFocused)
                .onExitCommand { close() }
            // O X limpa a busca; no Compacto aberto, também fecha e devolve os botões.
            if !search.query.isEmpty || expanded {
                Image(systemName: "xmark.circle.fill").foregroundStyle(theme.mutedText)
                    .onTapGesture { close() }
                    .accessibilityLabel("Fechar a busca")
            }
        }
        .font(.system(size: 12))
        .padding(.horizontal, 10)
        .frame(maxWidth: compact ? .infinity : 340)
        .frame(height: 24)
        .skinField()
        .contentShape(Rectangle())
        .onTapGesture { searchFocused = true }
        .hint("Buscar (⌘F)", "Procura músicas por título, artista ou álbum em toda a sua biblioteca. Esc limpa.")
        .background { GeometryReader { geo in Color.clear.onChange(of: geo.frame(in: .global), initial: true) { _, f in fieldFrame = f } } }
    }

    /// Abre a busca (no Compacto, ela ocupa a barra) e põe o cursor no campo.
    private func open() {
        if compact { expanded = true }
        DispatchQueue.main.async { searchFocused = true }
    }

    /// Limpa, tira o foco e (no Compacto) fecha a busca.
    private func close() {
        search.query = ""
        collapse()
    }

    /// Fecha a busca aberta sem apagar o que foi digitado (o resultado continua na lista).
    private func collapse() {
        searchFocused = false
        expanded = false
        NSApp.keyWindow?.makeFirstResponder(nil)
    }

    /// Clique em qualquer lugar fora da caixa fecha a busca aberta (o clique segue para onde foi dado).
    private func watchClicksOutside() {
        stopWatching()
        clickMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { event in
            guard let height = event.window?.contentView?.bounds.height else { return event }
            let point = CGPoint(x: event.locationInWindow.x, y: height - event.locationInWindow.y)
            if !fieldFrame.contains(point) { DispatchQueue.main.async { collapse() } }
            return event
        }
    }

    private func stopWatching() {
        if let clickMonitor { NSEvent.removeMonitor(clickMonitor) }
        clickMonitor = nil
    }
}

/// Voltar/Avançar: observam o navegador (a MainView não observa, e os botões ficavam desatualizados).
private struct HistoryButtons: View {
    @ObservedObject var browser: LibraryBrowser

    var body: some View {
        HStack(spacing: 3) {
            Button { browser.goBack() } label: { Image(systemName: "chevron.left").frame(width: 14) }
                .disabled(browser.backStack.isEmpty)
                .accessibilityLabel("Voltar")
                .hint("Voltar (⌘[)", "Volta para a pasta ou tela anterior da lista.")
            Button { browser.goForward() } label: { Image(systemName: "chevron.right").frame(width: 14) }
                .disabled(browser.forwardStack.isEmpty)
                .accessibilityLabel("Avançar")
                .hint("Avançar (⌘])", "Vai de novo para onde você estava antes de voltar.")
        }
        .buttonStyle(SkinButtonStyle(compact: true))
    }
}

/// Área do cabeçalho que arrasta a janela (a barra de título está oculta).
private struct DragArea: NSViewRepresentable {
    final class DragView: NSView {
        override var mouseDownCanMoveWindow: Bool { true }
    }

    func makeNSView(context: Context) -> NSView { DragView() }
    func updateNSView(_ nsView: NSView, context: Context) {}
}
