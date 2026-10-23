import AppKit
import SwiftUI

/// Modo mini: uma barra pequena sempre por cima das outras janelas (como o Winamp em modo "windowshade").
struct MiniPlayerView: View {
    @ObservedObject var state: PlayerState
    @ObservedObject private var clock: PlaybackClock
    let onExpand: () -> Void
    @AppStorage("themeID") private var themeID = Theme.graphite.id

    init(state: PlayerState, onExpand: @escaping () -> Void) {
        self.state = state
        self.clock = state.clock
        self.onExpand = onExpand
    }

    var body: some View {
        let theme = Theme.named(themeID)
        HStack(spacing: 10) {
            Group {
                if let cover = state.cover {
                    Image(nsImage: cover).resizable().scaledToFill()
                } else {
                    Image(systemName: "music.note").foregroundStyle(theme.mutedText)
                        .frame(maxWidth: .infinity, maxHeight: .infinity).background(Color.white.opacity(0.06))
                }
            }
            .frame(width: 44, height: 44)
            .clipShape(RoundedRectangle(cornerRadius: 5))
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(state.currentTrack?.title ?? "Nada tocando")
                    .font(.system(size: 12, weight: .semibold)).lineLimit(1).foregroundStyle(theme.text)
                Text(state.currentTrack?.artist ?? "")
                    .font(.system(size: 11)).lineLimit(1).foregroundStyle(theme.mutedText)
                ProgressBar(value: clock.progress, tint: theme.accent) { state.seek(to: $0) }
                    .frame(height: 4)
            }
            .frame(minWidth: 140)
            HStack(spacing: 2) {
                control("backward.fill", "Anterior") { state.step(by: -1) }
                control(state.isPlaying ? "pause.fill" : "play.fill", state.isPlaying ? "Pausar" : "Tocar") { state.togglePlay() }
                control("forward.fill", "Próxima") { state.step(by: 1) }
            }
            control("arrow.up.left.and.arrow.down.right", "Voltar ao player completo", action: onExpand)
        }
        .padding(.horizontal, 10)
        .frame(width: 400, height: 64)
        .background(LinearGradient(colors: [theme.windowTop, theme.windowBottom], startPoint: .top, endPoint: .bottom))
        .environment(\.theme, theme)
        .background(FloatingWindow())
        .preferredColorScheme(.dark)
        // Fechado por qualquer caminho (⌘W, menu): a janela principal volta.
        .onDisappear { MiniMode.showMain() }
    }

    private func control(_ symbol: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 13)).frame(width: 28, height: 28)
        }
        .buttonStyle(.plain)
        .help(label)
        .accessibilityLabel(label)
    }
}

/// Barra de progresso fina, clicável para pular.
private struct ProgressBar: View {
    let value: Double
    let tint: Color
    let onSeek: (Double) -> Void

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.12))
                Capsule().fill(tint).frame(width: max(0, geo.size.width * value))
            }
            .contentShape(Rectangle())
            .onTapGesture { location in onSeek(min(max(location.x / max(geo.size.width, 1), 0), 1)) }
        }
        .accessibilityElement()
        .accessibilityLabel("Posição da música")
        .accessibilityValue("\(Int(value * 100))%")
        .accessibilityAdjustableAction { direction in
            onSeek(min(max(value + (direction == .increment ? 0.05 : -0.05), 0), 1))
        }
    }
}

/// Deixa a janela sempre por cima, em todos os espaços, e arrastável por qualquer ponto.
private struct FloatingWindow: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            guard let w = view.window else { return }
            w.level = .floating
            w.collectionBehavior.insert(.canJoinAllSpaces)
            w.isMovableByWindowBackground = true
            w.titlebarAppearsTransparent = true
            w.titleVisibility = .hidden
            w.standardWindowButton(.zoomButton)?.isHidden = true
            w.standardWindowButton(.miniaturizeButton)?.isHidden = true
            w.standardWindowButton(.closeButton)?.isHidden = true
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

/// Alterna entre a janela principal e o modo mini.
@MainActor
enum MiniMode {
    static func enter(openWindow: OpenWindowAction) {
        mainWindow?.orderOut(nil)
        openWindow(id: "mini")
    }

    static func exit(openWindow: OpenWindowAction) {
        NSApp.windows.first { $0.identifier?.rawValue.hasPrefix("mini") == true }?.close()
        if mainWindow == nil { openWindow(id: "main") } else { showMain() }
    }

    static func showMain() {
        mainWindow?.makeKeyAndOrderFront(nil)
    }

    private static var mainWindow: NSWindow? {
        NSApp.windows.first { $0.identifier?.rawValue.hasPrefix("main") == true }
    }
}
