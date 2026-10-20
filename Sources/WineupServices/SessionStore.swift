import Foundation
import WineupCore
import WineupLibrary

public struct SessionSnapshot: Codable, Sendable, Equatable {
    public var version: Int
    public var entries: [QueueEntry]
    public var currentIndex: Int?
    public var position: Double
    public var repeatMode: RepeatMode
    public var shuffled: Bool
    public var seed: UInt64

    public init(version: Int = 1, entries: [QueueEntry], currentIndex: Int?, position: Double,
                repeatMode: RepeatMode, shuffled: Bool, seed: UInt64) {
        self.version = version
        self.entries = entries
        self.currentIndex = currentIndex
        self.position = position
        self.repeatMode = repeatMode
        self.shuffled = shuffled
        self.seed = seed
    }

    /// Remove entradas cujo arquivo sumiu, ajustando o índice atual.
    public func restorable(fileExists: (URL) -> Bool) -> SessionSnapshot {
        var kept: [QueueEntry] = []
        var newCurrent: Int?
        var currentSurvived = false
        for (i, e) in entries.enumerated() {
            guard fileExists(e.url) else { continue }
            if i == currentIndex { newCurrent = kept.count; currentSurvived = true }
            kept.append(e)
        }
        var copy = self
        copy.entries = kept
        copy.currentIndex = currentSurvived ? newCurrent : nil
        if !currentSurvived { copy.position = 0 }
        return copy
    }
}

/// Fila, faixa atual e posição em `app_setting` (`session.v1`).
public struct SessionStore: Sendable {
    static let maxEntries = 10_000
    private let settings: SettingsStore

    public init(db: LibraryDatabase) { settings = SettingsStore(db: db) }

    public func save(_ snapshot: SessionSnapshot) throws {
        let data = try JSONEncoder().encode(snapshot)
        guard let text = String(data: data, encoding: .utf8) else { return }
        try settings.set(SettingsStore.Keys.session, text)
    }

    public func load() -> SessionSnapshot? {
        guard let raw = try? settings.string(SettingsStore.Keys.session),
              let data = raw.data(using: .utf8),
              var snap = try? JSONDecoder().decode(SessionSnapshot.self, from: data),
              snap.version == 1 else { return nil }
        if snap.entries.count > Self.maxEntries { snap.entries = Array(snap.entries.prefix(Self.maxEntries)) }
        if let c = snap.currentIndex, !snap.entries.indices.contains(c) { snap.currentIndex = nil }
        if !snap.position.isFinite || snap.position < 0 { snap.position = 0 }
        return snap
    }
}
