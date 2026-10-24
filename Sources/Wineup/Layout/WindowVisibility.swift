import AppKit
import SwiftUI

/// A janela principal está visível? (minimizada, escondida ou coberta por outras = não).
/// Medidor e animações param enquanto ninguém os vê.
@MainActor
final class WindowVisibility: ObservableObject {
    static let shared = WindowVisibility()

    @Published private(set) var mainVisible = true
    private weak var window: NSWindow?
    private var observers: [NSObjectProtocol] = []

    /// Passa a acompanhar a janela principal (chamar de novo com a mesma janela não faz nada).
    func track(_ newWindow: NSWindow) {
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

extension EnvironmentValues {
    var animationsPaused: Bool {
        get { self[AnimationsPausedKey.self] }
        set { self[AnimationsPausedKey.self] = newValue }
    }
}
