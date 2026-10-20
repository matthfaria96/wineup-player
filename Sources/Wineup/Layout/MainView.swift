import AppKit
import SwiftUI

struct MainView: View {
    @ObservedObject var state: PlayerState
    @Binding var layoutRaw: String
    @Binding var themeID: String

    var body: some View {
        let theme = Theme.named(themeID)
        let layout = LayoutMode.named(layoutRaw)

        VStack(spacing: 6) {
            header(theme: theme)
            Group {
                switch layout {
                case .grid: GridLayout(state: state)
                case .compact: CompactLayout(state: state)
                case .studio: StudioLayout(state: state)
                }
            }
            .padding([.horizontal, .bottom], 8)
        }
        .environment(\.theme, theme)
        .background(
            LinearGradient(colors: [theme.windowTop, theme.windowBottom], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
        )
        .frame(minWidth: layout.minSize.width, minHeight: layout.minSize.height)
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

/// Área do cabeçalho que arrasta a janela (a barra de título está oculta).
private struct DragArea: NSViewRepresentable {
    final class DragView: NSView {
        override var mouseDownCanMoveWindow: Bool { true }
    }

    func makeNSView(context: Context) -> NSView { DragView() }
    func updateNSView(_ nsView: NSView, context: Context) {}
}
