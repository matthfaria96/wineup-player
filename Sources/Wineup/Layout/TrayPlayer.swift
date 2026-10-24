import AppKit
import Combine
import SwiftUI
import WineupCore

/// Modo barra de menus: a janela fecha, o ícone do Dock some e o player fica no topo do Mac.
/// Clicar no ícone abre o painel com a música, os controles e as próximas da fila.
@MainActor
enum TrayMode {
    static var isOn: Bool { TrayController.shared.isShown }

    static func enter(state: PlayerState, openWindow: OpenWindowAction) {
        TrayController.shared.show(state: state, openWindow: openWindow)
        for window in NSApp.windows where window.identifier?.rawValue.hasPrefix("main") == true { window.close() }
        NSApp.setActivationPolicy(.accessory)
    }

    static func exit(openWindow: OpenWindowAction) {
        TrayController.shared.hide()
        NSApp.setActivationPolicy(.regular)
        if let main = NSApp.windows.first(where: { $0.identifier?.rawValue.hasPrefix("main") == true }) {
            main.makeKeyAndOrderFront(nil)
        } else {
            openWindow(id: "main")
        }
        NSApp.activate(ignoringOtherApps: true)
    }
}

/// Item da barra de menus (AppKit): título curto da música e o painel num popover.
@MainActor
final class TrayController: NSObject {
    static let shared = TrayController()

    private var item: NSStatusItem?
    private let popover = NSPopover()
    private let status = TrayStatus()
    private var subscription: AnyCancellable?

    var isShown: Bool { item != nil }

    func show(state: PlayerState, openWindow: OpenWindowAction) {
        guard item == nil else { return }
        status.bind(state)
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        // Sem isto o macOS cria o item invisível (fica escondido até o usuário mexer na barra).
        item.autosaveName = "WineupPlayerTray"
        item.isVisible = true
        item.button?.target = self
        item.button?.action = #selector(toggle)
        item.button?.imagePosition = .imageLeading
        item.button?.setAccessibilityLabel("Wineup Player")
        self.item = item
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(
            rootView: TrayPlayerView(state: state, onExit: { [weak self] in
                self?.popover.performClose(nil)
                TrayMode.exit(openWindow: openWindow)
            }).preferredColorScheme(.dark))
        subscription = status.objectWillChange.receive(on: DispatchQueue.main).sink { [weak self] _ in
            DispatchQueue.main.async { self?.refresh() }
        }
        refresh()
    }

    func hide() {
        popover.performClose(nil)
        subscription = nil
        if let item { NSStatusBar.system.removeStatusItem(item) }
        item = nil
    }

    private func refresh() {
        guard let button = item?.button else { return }
        button.image = NSImage(systemSymbolName: status.playing ? "waveform" : "music.note",
                               accessibilityDescription: status.playing ? "Tocando" : "Pausado")
        button.title = status.title.map { " " + $0 } ?? ""
    }

    @objc private func toggle() {
        guard let button = item?.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }
}

/// Só o que o ícone da barra de menus mostra (título e se está tocando), publicado quando muda.
/// O ícone não observa o player inteiro: ele atualiza várias vezes por segundo e a barra de menus
/// redesenhava sem parar.
@MainActor
final class TrayStatus: ObservableObject {
    @Published private(set) var title: String?
    @Published private(set) var playing = false
    private var subscription: AnyCancellable?

    func bind(_ state: PlayerState) {
        guard subscription == nil else { return }
        let playing: AnyPublisher<Bool, Never> = state.$isPlaying.removeDuplicates().eraseToAnyPublisher()
        let track: AnyPublisher<TrackID?, Never> = state.$currentID.removeDuplicates().eraseToAnyPublisher()
        subscription = playing.combineLatest(track)
            .receive(on: DispatchQueue.main)
            .sink { [weak self, weak state] isPlaying, _ in
                guard let self else { return }
                let title = state?.currentTrack.map { TrayLabel.short("\($0.title) — \($0.artist)") }
                if self.playing != isPlaying { self.playing = isPlaying }
                if self.title != title { self.title = title }
            }
    }
}

enum TrayLabel {
    static func short(_ s: String) -> String { s.count > 28 ? String(s.prefix(27)) + "…" : s }
}

/// Painel aberto pelo ícone da barra de menus.
struct TrayPlayerView: View {
    @ObservedObject var state: PlayerState
    @ObservedObject private var clock: PlaybackClock
    let onExit: () -> Void

    init(state: PlayerState, onExit: @escaping () -> Void) {
        self.state = state
        self.clock = state.clock
        self.onExit = onExit
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            nowPlaying
            progress
            controls
            volume
            Divider()
            upNext
            Divider()
            HStack {
                Button(action: onExit) {
                    Label("Abrir o Wineup", systemImage: "macwindow")
                }
                .help("Sair da barra de menus e voltar à tela normal")
                Spacer()
                Button("Sair do Wineup") { NSApp.terminate(nil) }
            }
            .controlSize(.small)
        }
        .padding(14)
        .frame(width: 340)
    }

    private var nowPlaying: some View {
        HStack(spacing: 12) {
            Group {
                if let cover = state.cover {
                    Image(nsImage: cover).resizable().scaledToFill()
                } else {
                    Image(systemName: "music.note").font(.system(size: 24)).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity).background(Color.secondary.opacity(0.15))
                }
            }
            .frame(width: 72, height: 72)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(state.currentTrack?.title ?? "Nada tocando").font(.system(size: 14, weight: .semibold)).lineLimit(2)
                Text(state.currentTrack?.artist ?? "").font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1)
                Text([state.currentTrack?.album, state.currentTrack?.year].compactMap { $0 }.joined(separator: " · "))
                    .font(.system(size: 11)).foregroundStyle(.tertiary).lineLimit(1)
            }
        }
    }

    private var progress: some View {
        VStack(spacing: 3) {
            Slider(value: Binding(get: { clock.progress }, set: { state.seek(to: $0) }), in: 0...1)
                .controlSize(.mini)
                .disabled(state.currentTrack == nil)
                .accessibilityLabel("Posição da música")
            HStack {
                Text(LyricsBox.time(state.elapsedInTrack))
                Spacer()
                Text("-" + LyricsBox.time(Double(state.remainingSeconds)))
            }
            .font(.system(size: 10)).monospacedDigit().foregroundStyle(.secondary)
        }
    }

    private var controls: some View {
        HStack(spacing: 18) {
            control(state.shuffleOn ? "shuffle.circle.fill" : "shuffle", "Aleatório", size: 14, on: state.shuffleOn) {
                state.shuffleOn.toggle()
            }
            control("backward.fill", "Anterior", size: 17) { state.step(by: -1) }
            control(state.isPlaying ? "pause.circle.fill" : "play.circle.fill", state.isPlaying ? "Pausar" : "Tocar", size: 34) {
                state.togglePlay()
            }
            control("forward.fill", "Próxima", size: 17) { state.step(by: 1) }
            control(state.repeatMode == .one ? "repeat.1" : "repeat", "Repetir", size: 14, on: state.repeatMode != .off) {
                state.repeatMode = state.repeatMode == .off ? .all : state.repeatMode == .all ? .one : .off
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var volume: some View {
        HStack(spacing: 8) {
            Image(systemName: "speaker.fill").font(.system(size: 10)).foregroundStyle(.secondary)
            TrayVolumeSlider(mixer: state.mixer)
            Image(systemName: "speaker.wave.3.fill").font(.system(size: 10)).foregroundStyle(.secondary)
        }
    }

    private var upNext: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("A seguir").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
            let next = state.upcoming(limit: 8)
            if next.isEmpty {
                Text("Nada na fila depois desta música.").font(.system(size: 11)).foregroundStyle(.tertiary)
            }
            ForEach(next, id: \.index) { item in
                Button { state.playQueueIndex(item.index) } label: {
                    HStack(spacing: 8) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(item.track.title).font(.system(size: 12)).lineLimit(1)
                            Text(item.track.artist).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer()
                        Text(LyricsBox.time(Double(item.track.duration))).font(.system(size: 10)).monospacedDigit().foregroundStyle(.tertiary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Tocar agora")
            }
        }
    }

    private func control(_ symbol: String, _ label: String, size: CGFloat, on: Bool = false,
                         action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: size))
                .foregroundStyle(on ? Color.accentColor : .primary)
        }
        .buttonStyle(.plain)
        .help(label)
        .accessibilityLabel(label)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

extension PlayerState {
    /// Próximas músicas da fila, na ordem em que vão tocar (inclui o aleatório e o "repetir todas").
    func upcoming(limit: Int) -> [(index: Int, track: Track)] {
        let q = queue
        guard let current = q.currentIndex, !q.items.isEmpty else { return [] }
        let order = q.isShuffled && q.shuffleOrder.count == q.items.count ? q.shuffleOrder : Array(q.items.indices)
        guard let position = order.firstIndex(of: current) else { return [] }
        var after = Array(order[(position + 1)...])
        if q.repeatMode == .all { after += order[..<position] }
        return after.prefix(limit).map { ($0, q.items[$0]) }
    }

    func playQueueIndex(_ index: Int) {
        guard queue.items.indices.contains(index) else { return }
        queue = queue.selecting(index: index)
        startCurrentPublic()
    }
}

/// Volume do painel da barra de menus (observa só o mixer).
private struct TrayVolumeSlider: View {
    @ObservedObject var mixer: MixerModel

    var body: some View {
        Slider(value: $mixer.volume, in: 0...1).controlSize(.mini).accessibilityLabel("Volume")
    }
}
