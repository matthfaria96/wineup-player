import AppKit
import SwiftUI

/// A janela principal está visível? (minimizada, escondida ou coberta por outras = não).
/// Medidor e animações param enquanto ninguém os vê.
@MainActor
final class WindowVisibility: ObservableObject {
    static let shared = WindowVisibility()

    @Published private(set) var mainVisible = true
    /// Música tocando com o Wineup em uso: animações no ritmo cheio; senão, no ritmo calmo.
    @Published private(set) var lively = false
    private weak var window: NSWindow?
    private var observers: [NSObjectProtocol] = []
    private var appObservers: [NSObjectProtocol] = []
    private var playing = false

    /// Chave do ajuste "Animar o fundo do skin".
    static let skinAnimationKey = "skin.animations"

    /// Ritmo das animações do skin e das cenas (quadros por segundo).
    var animationFPS: Double { lively ? 20 : 10 }

    func setPlaying(_ value: Bool) {
        playing = value
        updateLively()
    }

    private func updateLively() {
        let value = playing && NSApp.isActive
        if value != lively { lively = value }
    }

    /// Passa a acompanhar a janela principal (chamar de novo com a mesma janela não faz nada).
    func track(_ newWindow: NSWindow) {
        if appObservers.isEmpty {
            let names = [NSApplication.didBecomeActiveNotification, NSApplication.didResignActiveNotification]
            appObservers = names.map { name in
                NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.updateLively() }
                }
            }
        }
        guard newWindow !== window else { return }
        window = newWindow
        observers.forEach(NotificationCenter.default.removeObserver)
        let center = NotificationCenter.default
        let names: [Notification.Name] = [NSWindow.didChangeOcclusionStateNotification,
                                          NSWindow.didMiniaturizeNotification,
                                          NSWindow.didDeminiaturizeNotification,
                                          NSWindow.willCloseNotification]
        observers = names.map { name in
            center.addObserver(forName: name, object: newWindow, queue: .main) { [weak self] note in
                MainActor.assumeIsolated {
                    if note.name == NSWindow.willCloseNotification { self?.set(false) } else { self?.update() }
                }
            }
        }
        update()
    }

    private func update() {
        guard let window else { set(false); return }
        set(window.isVisible && !window.isMiniaturized && window.occlusionState.contains(.visible))
    }

    private func set(_ visible: Bool) {
        if visible != mainVisible { mainVisible = visible }
    }
}

/// Animações da janela pausadas (a janela não está visível).
private struct AnimationsPausedKey: EnvironmentKey { static let defaultValue = false }

/// Quadros por segundo das animações (cheio tocando, calmo parado ou com outro app em uso).
private struct AnimationFPSKey: EnvironmentKey { static let defaultValue = 20.0 }

extension EnvironmentValues {
    var animationsPaused: Bool {
        get { self[AnimationsPausedKey.self] }
        set { self[AnimationsPausedKey.self] = newValue }
    }

    var animationFPS: Double {
        get { self[AnimationFPSKey.self] }
        set { self[AnimationFPSKey.self] = newValue }
    }
}
