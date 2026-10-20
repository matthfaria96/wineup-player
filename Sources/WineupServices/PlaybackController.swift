import Foundation
import WineupCore

public struct QueueEntry: Hashable, Sendable, Codable {
    public let fileID: Int64?
    public let url: URL
    public let title: String
    public let artist: String
    public let duration: Double?

    public init(fileID: Int64?, url: URL, title: String, artist: String, duration: Double?) {
        self.fileID = fileID
        self.url = url
        self.title = title
        self.artist = artist
        self.duration = duration
    }
}

/// Fila de reprodução sobre o protocolo `AudioEngine`: repetir, embaralhar e gapless.
@MainActor
public final class PlaybackController {
    private let engine: AudioEngine
    public private(set) var queue = PlaybackQueue<QueueEntry>()
    public private(set) var lastError: String?
    public var onCurrentChanged: ((QueueEntry?) -> Void)?

    public init(engine: AudioEngine) { self.engine = engine }

    // MARK: - Edição da fila

    public func replaceQueue(_ entries: [QueueEntry], startAt: Int, autoplay: Bool) {
        let keepRepeat = queue.repeatMode
        let wasShuffled = queue.isShuffled
        let seed = queue.seed
        var fresh = PlaybackQueue(items: entries, currentIndex: entries.indices.contains(startAt) ? startAt : nil)
            .withRepeat(keepRepeat)
        if wasShuffled { fresh = fresh.shuffled(seed: seed) }
        queue = fresh
        if autoplay { playCurrent() } else { onCurrentChanged?(queue.current); enqueueUpcoming() }
    }

    public func append(_ entries: [QueueEntry]) {
        queue = queue.appending(entries)
        enqueueUpcoming()
    }

    public func playNext(_ entries: [QueueEntry]) {
        let at = (queue.currentIndex ?? -1) + 1
        queue = queue.inserting(entries, at: at)
        enqueueUpcoming()
    }

    public func move(from source: IndexSet, to destination: Int) {
        queue = queue.moving(from: source, to: destination)
        enqueueUpcoming()
    }

    public func remove(at index: Int) {
        let removedCurrent = queue.currentIndex == index
        queue = queue.removing(at: index)
        if removedCurrent {
            if queue.current != nil { playCurrent() } else { engine.stop(); onCurrentChanged?(nil) }
        } else {
            enqueueUpcoming()
        }
    }

    // MARK: - Navegação

    public func select(index: Int) {
        guard queue.items.indices.contains(index) else { return }
        queue = queue.selecting(index: index)
        playCurrent()
    }

    public func next() {
        guard let advanced = queue.advanced() else { return }
        queue = advanced
        playCurrent()
    }

    public func previous() {
        guard let i = queue.previousIndex() else { return }
        queue = queue.selecting(index: i)
        playCurrent()
    }

    public func setRepeat(_ mode: RepeatMode) {
        queue = queue.withRepeat(mode)
        enqueueUpcoming()
    }

    public func setShuffle(_ on: Bool, seed: UInt64 = .random(in: 0...UInt64.max)) {
        queue = on ? queue.shuffled(seed: seed) : queue.unshuffled()
        enqueueUpcoming()
    }

    // MARK: - Eventos do motor

    public func handleNowPlayingChanged(url: URL?) {
        guard let url else { return }
        if queue.current?.url == url { return }
        if let predicted = queue.nextIndex(), queue.items[predicted].url == url {
            queue = queue.selecting(index: predicted)
        } else if let found = queue.items.firstIndex(where: { $0.url == url }) {
            queue = queue.selecting(index: found)
        } else {
            return
        }
        onCurrentChanged?(queue.current)
        enqueueUpcoming()
    }

    public func handleEndOfAudio() {
        guard queue.repeatMode == .off else { return }
        queue = PlaybackQueue(items: queue.items, currentIndex: nil)
            .withRepeat(queue.repeatMode)
        onCurrentChanged?(nil)
    }

    // MARK: - Interno

    private func playCurrent() {
        guard let entry = queue.current else { return }
        do {
            try engine.play(entry.url)
            lastError = nil
        } catch {
            lastError = String(describing: error)
        }
        onCurrentChanged?(entry)
        enqueueUpcoming()
    }

    private func enqueueUpcoming() {
        guard let i = queue.nextIndex(), queue.items.indices.contains(i) else { return }
        try? engine.enqueue(queue.items[i].url)
    }
}
