import AppKit

/// Atalhos clássicos do Winamp na janela principal:
/// Z anterior · X tocar (ou recomeçar) · C pausar/continuar · V parar · B próxima · espaço tocar/pausar
/// ← / → volta/avança 5 s · ↑ / ↓ volume (quando a lista não está com o foco).
/// Nunca agem enquanto o usuário digita num campo de texto.
@MainActor
enum ClassicKeys {
    private static var monitor: Any?

    static func install(state: PlayerState) {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak state] event in
            guard let state, handle(event, state: state) else { return event }
            return nil
        }
    }

    /// true = a tecla foi usada (não segue adiante).
    static func handle(_ event: NSEvent, state: PlayerState) -> Bool {
        guard event.modifierFlags.intersection([.command, .control, .option]).isEmpty,
              let window = event.window, window.identifier?.rawValue.hasPrefix("main") == true,
              !isTyping(in: window) else { return false }
        switch event.keyCode {
        case 123: state.seek(bySeconds: -5); return true             // ←
        case 124: state.seek(bySeconds: 5); return true              // →
        case 126, 125:                                               // ↑ ↓
            if listHasFocus(in: window) { return false }
            state.volume = min(1, max(0, state.volume + (event.keyCode == 126 ? 0.05 : -0.05)))
            return true
        case 49: state.togglePlay(); return true                     // espaço
        default: break
        }
        switch event.charactersIgnoringModifiers?.lowercased() {
        case "z": state.step(by: -1)
        case "x": if state.isPlaying { state.seek(to: 0) } else { state.togglePlay() }
        case "c": if state.currentTrack != nil { state.togglePlay() }
        case "v": state.stop()
        case "b": state.step(by: 1)
        default: return false
        }
        return true
    }

    private static func isTyping(in window: NSWindow) -> Bool {
        guard let responder = window.firstResponder else { return false }
        return responder is NSText || responder is NSTextField
    }

    private static func listHasFocus(in window: NSWindow) -> Bool {
        window.firstResponder is NSTableView || window.firstResponder is NSCollectionView
    }
}

extension PlayerState {
    /// Avança/volta alguns segundos na faixa atual.
    func seek(bySeconds seconds: Double) {
        guard let track = currentTrack else { return }
        let length = track.end.map { $0 - (track.start ?? 0) } ?? Double(track.duration)
        guard length > 0 else { return }
        seek(to: progress + seconds / length)
    }
}
