import AppKit
import SwiftUI

struct MainView: View {
    @ObservedObject var state: PlayerState
    @Binding var layoutRaw: String
    @Binding var themeID: String
    @StateObject private var model = MainViewModel()

    var body: some View {
        let theme = Theme.named(themeID)
        let layout = LayoutMode.named(layoutRaw)

        VStack(spacing: 6) {
            header(theme: theme)
            ArrangedLayout(state: state, mode: layout, columns: $model.columns)
                .padding([.horizontal, .bottom], 8)
        }
        .environment(\.theme, theme)
        .background(
            LinearGradient(colors: [theme.windowTop, theme.windowBottom], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
        )
        .frame(minWidth: layout.minSize.width, minHeight: layout.minSize.height)
        .background(WindowAccessor(onWindow: { model.window = $0 }))
        .onAppear { model.columns = layout.columns(); resizeWindow(for: layout) }
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

    private func header(theme: Theme) -> some View {
        HStack {
            Spacer()
            Text("Wineup Player")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(theme.mutedText)
            Spacer()
            Menu {
                Picker("Layout", selection: $layoutRaw) {
                    ForEach(LayoutMode.allCases) { Text($0.name).tag($0.rawValue) }
                }
                Picker("Tema", selection: $themeID) {
                    ForEach(Theme.all) { Text($0.name).tag($0.id) }
                }
                Picker("Estilo da lista", selection: $state.listStyle) {
                    ForEach(ListStyle.allCases) { Text($0.title).tag($0) }
                }
                Picker("Ver biblioteca por", selection: Binding(get: { state.browser.mode }, set: { state.browser.mode = $0 })) {
                    ForEach(BrowseMode.allCases) { Text($0.title).tag($0) }
                }
            } label: {
                Label("Design de exibição", systemImage: "rectangle.3.group")
                    .labelStyle(.titleAndIcon)
                    .font(.system(size: 11))
                    .foregroundStyle(theme.mutedText)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
        .padding(.horizontal, 12)
        .frame(height: 28)
        .background(DragArea())
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
            case .full: target = max(window.frame.width, 1280)
            }
            var frame = window.frame
            let top = frame.maxY
            frame.size.width = target
            if mode == .compact { frame.size.height = max(frame.height, 820) }
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
