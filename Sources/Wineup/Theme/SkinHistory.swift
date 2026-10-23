import Foundation
import WineupLibrary

/// Desfazer/refazer das edições de skin (por skin). Mudanças seguidas em menos de 0,8 s
/// (arrastar um slider, mover um ponto) viram um passo só.
@MainActor
final class SkinHistory: ObservableObject {
    static let shared = SkinHistory()

    private struct Stack { var undo: [SkinManifest] = []; var redo: [SkinManifest] = []; var last = Date.distantPast }
    @Published private var stacks: [String: Stack] = [:]
    private let limit = 100

    func canUndo(_ id: String) -> Bool { !(stacks[id]?.undo.isEmpty ?? true) }
    func canRedo(_ id: String) -> Bool { !(stacks[id]?.redo.isEmpty ?? true) }

    /// Guarda `before` antes de gravar uma mudança.
    func record(_ before: SkinManifest) {
        var s = stacks[before.id] ?? Stack()
        let now = Date()
        if now.timeIntervalSince(s.last) > 0.8 || s.undo.isEmpty {
            s.undo.append(before)
            if s.undo.count > limit { s.undo.removeFirst() }
        }
        s.last = now
        s.redo = []
        stacks[before.id] = s
    }

    /// Devolve o estado a gravar (e guarda o atual para refazer).
    func undo(current: SkinManifest) -> SkinManifest? {
        guard var s = stacks[current.id], let previous = s.undo.popLast() else { return nil }
        s.redo.append(current)
        s.last = .distantPast
        stacks[current.id] = s
        return previous
    }

    func redo(current: SkinManifest) -> SkinManifest? {
        guard var s = stacks[current.id], let next = s.redo.popLast() else { return nil }
        s.undo.append(current)
        s.last = .distantPast
        stacks[current.id] = s
        return next
    }

    /// Ao restaurar um oficial ou apagar, o histórico daquele skin deixa de valer.
    func reset(_ id: String) { stacks[id] = nil }
}
