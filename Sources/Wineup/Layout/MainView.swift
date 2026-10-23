import WineupLibrary
import AppKit
import SwiftUI

struct MainView: View {
    @ObservedObject var state: PlayerState
    @Binding var layoutRaw: String
    @Binding var themeID: String
    @StateObject private var model = MainViewModel()
    @Environment(\.openWindow) private var openWindow
    /// Foco da busca: clicar na caixa (ou ⌘F) põe o cursor no campo.
    @FocusState private var searchFocused: Bool
    /// Editar um tema no editor redesenha a janela na hora.
    @ObservedObject private var skins = SkinStore.shared

    var body: some View {
        let theme = Theme.named(themeID)
        let layout = LayoutMode.named(layoutRaw)

        VStack(spacing: 6) {
            header(theme: theme, compact: layout == .compact)
            ArrangedLayout(state: state, mode: layout, columns: $model.columns)
                .padding([.horizontal, .bottom], 8)
        }
        .ignoresSafeArea(.container, edges: .top)
        .environment(\.theme, theme)
        .background {
            ZStack {
                LinearGradient(colors: [theme.windowTop, theme.windowBottom], startPoint: .top, endPoint: .bottom)
                // Skin: arte de fundo da janela e as camadas animadas (estrelas, redemoinhos...).
                if let art = theme.art, art.manifest.window.background != nil || !art.manifest.window.layers.isEmpty {
                    SkinFillView(art: art, fill: art.manifest.window.background, layers: art.manifest.window.layers,
                                 energy: SkinEnergy.value)
                    // Leve escurecimento no topo (sem contorno): título e botões legíveis sobre a arte.
                    VStack(spacing: 0) {
                        LinearGradient(colors: [.black.opacity(0.55), .black.opacity(0)], startPoint: .top, endPoint: .bottom)
                            .frame(height: 64)
                        Spacer(minLength: 0)
                    }
                }
            }
            // Arte e animação do fundo nunca recebem cliques (o desenho assíncrono cria uma camada própria).
            .allowsHitTesting(false)
            .ignoresSafeArea()
        }
        .frame(minWidth: layout.minSize.width, minHeight: layout.minSize.height)
        .background(WindowAccessor(onWindow: { window in
            let first = model.window == nil
            model.window = window
            // Ao abrir, ninguém fica com o foco (a busca não captura o teclado).
            if first { DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { window.makeFirstResponder(nil) } }
        }))
        .onAppear {
            model.columns = layout.columns()
            resizeWindow(for: layout)
            // A janela não abre com o foco na busca (não captura o teclado sozinha).
            DispatchQueue.main.async { model.window?.makeFirstResponder(nil) }
        }
        .onChange(of: layoutRaw) { _, raw in
            let mode = LayoutMode.named(raw)
            model.columns = mode.columns()
            resizeWindow(for: mode)
        }
        .preferredColorScheme(.dark)
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
        HStack(spacing: 8) {
            HStack(spacing: 3) {
                Button { state.browser.goBack() } label: { Image(systemName: "chevron.left").frame(width: 14) }
                    .disabled(state.browser.backStack.isEmpty)
                    .accessibilityLabel("Voltar")
                Button { state.browser.goForward() } label: { Image(systemName: "chevron.right").frame(width: 14) }
                    .disabled(state.browser.forwardStack.isEmpty)
                    .accessibilityLabel("Avançar")
            }
            .buttonStyle(SkinButtonStyle(compact: true))
            Button { openWindow(id: "metadata") } label: {
                if compact { Image(systemName: "tag") }
                else { Label("Metadados", systemImage: "tag").labelStyle(.titleAndIcon) }
            }
            .buttonStyle(SkinButtonStyle())
            .help("Metadados: gerenciador completo de tags, capas e letras")
            Spacer(minLength: 8)
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundStyle(theme.mutedText)
                TextField(compact ? "Buscar" : "Buscar em sua biblioteca…", text: $state.query)
                    .textFieldStyle(.plain)
                    .foregroundStyle(theme.text)
                    .focused($searchFocused)
                    .onExitCommand { state.query = ""; searchFocused = false }
                if !state.query.isEmpty {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(theme.mutedText)
                        .onTapGesture { state.query = "" }
                }
            }
            .font(.system(size: 12))
            .padding(.horizontal, 10)
            .frame(maxWidth: compact ? 150 : 340)
            .frame(height: 24)
            .skinField()
            .contentShape(Rectangle())
            .onTapGesture { searchFocused = true }
            .background {
                // ⌘F: vai para a busca.
                Button("") { searchFocused = true }.keyboardShortcut("f", modifiers: .command).opacity(0).allowsHitTesting(false)
            }
            Spacer(minLength: 8)
            Button { TrayMode.enter(state: state, openWindow: openWindow) } label: { Image(systemName: "menubar.arrow.up.rectangle") }
                .buttonStyle(SkinButtonStyle(compact: true))
                .help("Tocar pela barra de menus: fecha a janela e deixa o player no topo do Mac (⌥⌘M)")
                .accessibilityLabel("Tocar pela barra de menus")
            // Seletor de layout que mostra o modo atual (no Compacto, só o ícone).
            SkinMenu(help: "Layout: Padrão, Compacto ou Completo") {
                Picker("Layout", selection: $layoutRaw) {
                    ForEach(LayoutMode.allCases) { Text($0.name).tag($0.rawValue) }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            } label: {
                if compact {
                    Image(systemName: "square.grid.2x2")
                } else {
                    Label(LayoutMode.named(layoutRaw).name, systemImage: "square.grid.2x2").labelStyle(.titleAndIcon)
                }
            }
        }
        .font(.system(size: 11))
        .padding(.trailing, 10)
        .frame(height: 34)
    }
}

extension MainView {
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
            if mode == .compact { frame.size.height = max(frame.height, 820) }
            else { frame.size.height = max(frame.height, mode.minSize.height) }
            frame.origin.y = top - frame.height
            window.setFrame(frame, display: true, animate: true)
        }
    }
}

/// Dá acesso à NSWindow que hospeda a view.
private struct WindowAccessor: NSViewRepresentable {
    let onWindow: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { if let w = view.window { onWindow(w) } }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { if let w = nsView.window { onWindow(w) } }
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
