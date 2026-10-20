import Foundation

public enum RepeatMode: String, Codable, Sendable, CaseIterable {
    case off, one, all
}

/// Gerador determinístico (SplitMix64) para embaralhar com semente.
struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

/// Fila imutável: toda operação devolve uma nova fila.
public struct PlaybackQueue<Item: Hashable & Sendable>: Sendable, Equatable {
    public let items: [Item]
    public let currentIndex: Int?
    public let repeatMode: RepeatMode
    public let isShuffled: Bool
    public let shuffleOrder: [Int]
    public let seed: UInt64

    public init(items: [Item] = [], currentIndex: Int? = nil) {
        self.init(items: items, currentIndex: currentIndex, repeatMode: .off,
                  isShuffled: false, shuffleOrder: [], seed: 0)
    }

    private init(items: [Item], currentIndex: Int?, repeatMode: RepeatMode,
                 isShuffled: Bool, shuffleOrder: [Int], seed: UInt64) {
        self.items = items
        if let c = currentIndex, items.indices.contains(c) { self.currentIndex = c } else { self.currentIndex = nil }
        self.repeatMode = repeatMode
        self.isShuffled = isShuffled
        self.shuffleOrder = shuffleOrder
        self.seed = seed
    }

    public var current: Item? { currentIndex.map { items[$0] } }

    // MARK: - Edição

    public func appending(_ newItems: [Item]) -> PlaybackQueue {
        rebuilt(items: items + newItems, currentIndex: currentIndex)
    }

    public func inserting(_ newItems: [Item], at index: Int) -> PlaybackQueue {
        let at = min(max(index, 0), items.count)
        var out = items
        out.insert(contentsOf: newItems, at: at)
        var cur = currentIndex
        if let c = cur, at <= c { cur = c + newItems.count }
        return rebuilt(items: out, currentIndex: cur)
    }

    public func moving(from source: IndexSet, to destination: Int) -> PlaybackQueue {
        let valid = source.filter { items.indices.contains($0) }
        guard !valid.isEmpty else { return self }
        let dest = min(max(destination, 0), items.count)
        let moved = valid.sorted()
        let before = dest - moved.filter { $0 < dest }.count
        var order = Array(items.indices).filter { !moved.contains($0) }
        order.insert(contentsOf: moved, at: min(before, order.count))
        let newCurrent = currentIndex.flatMap { order.firstIndex(of: $0) }
        return rebuilt(items: order.map { items[$0] }, currentIndex: newCurrent)
    }

    public func removing(at index: Int) -> PlaybackQueue {
        guard items.indices.contains(index) else { return self }
        var out = items
        out.remove(at: index)
        var cur = currentIndex
        if let c = cur {
            if index < c { cur = c - 1 }
            else if index == c { cur = c < out.count ? c : nil }
        }
        return rebuilt(items: out, currentIndex: cur)
    }

    public func selecting(index: Int) -> PlaybackQueue {
        guard items.indices.contains(index) else { return self }
        // Mantém a ordem embaralhada: navegar não deve reembaralhar a fila.
        return PlaybackQueue(items: items, currentIndex: index, repeatMode: repeatMode,
                             isShuffled: isShuffled, shuffleOrder: shuffleOrder, seed: seed)
    }

    public func withRepeat(_ mode: RepeatMode) -> PlaybackQueue {
        PlaybackQueue(items: items, currentIndex: currentIndex, repeatMode: mode,
                      isShuffled: isShuffled, shuffleOrder: shuffleOrder, seed: seed)
    }

    public func shuffled(seed: UInt64) -> PlaybackQueue {
        PlaybackQueue(items: items, currentIndex: currentIndex, repeatMode: repeatMode,
                      isShuffled: true,
                      shuffleOrder: Self.makeOrder(count: items.count, current: currentIndex, seed: seed),
                      seed: seed)
    }

    public func unshuffled() -> PlaybackQueue {
        PlaybackQueue(items: items, currentIndex: currentIndex, repeatMode: repeatMode,
                      isShuffled: false, shuffleOrder: [], seed: seed)
    }

    // MARK: - Navegação

    public func nextIndex() -> Int? {
        guard let c = currentIndex else { return nil }
        if repeatMode == .one { return c }
        let seq = sequence
        guard let pos = seq.firstIndex(of: c) else { return nil }
        if pos + 1 < seq.count { return seq[pos + 1] }
        return repeatMode == .all ? seq.first : nil
    }

    public func previousIndex() -> Int? {
        guard let c = currentIndex else { return nil }
        if repeatMode == .one { return c }
        let seq = sequence
        guard let pos = seq.firstIndex(of: c) else { return nil }
        if pos > 0 { return seq[pos - 1] }
        return repeatMode == .all ? seq.last : nil
    }

    public func advanced() -> PlaybackQueue? {
        nextIndex().map { selecting(index: $0) }
    }

    // MARK: - Interno

    private var sequence: [Int] { isShuffled ? shuffleOrder : Array(items.indices) }

    private func rebuilt(items: [Item], currentIndex: Int?) -> PlaybackQueue {
        let valid = currentIndex.flatMap { items.indices.contains($0) ? $0 : nil }
        return PlaybackQueue(
            items: items, currentIndex: valid, repeatMode: repeatMode, isShuffled: isShuffled,
            shuffleOrder: isShuffled ? Self.makeOrder(count: items.count, current: valid, seed: seed) : [],
            seed: seed)
    }

    private static func makeOrder(count: Int, current: Int?, seed: UInt64) -> [Int] {
        var rest = Array(0..<count).filter { $0 != current }
        var rng = SplitMix64(seed: seed)
        rest.shuffle(using: &rng)
        return (current.map { [$0] } ?? []) + rest
    }
}
