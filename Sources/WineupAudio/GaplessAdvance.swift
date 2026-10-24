import Foundation
import WineupCore

/// Decide o que uma troca de faixa do player significa para a fila do app.
public enum GaplessAdvance {
    /// Índice da fila que passou a tocar sozinho (pré-enfileirado), ou nil se não for avanço da fila.
    /// Em "Repetir uma" o próximo é a própria faixa: devolve o índice atual (recomeçou).
    /// `fromQueue` false: a troca veio de play(), a fila já aponta para a faixa certa.
    public static func index<Item>(in queue: PlaybackQueue<Item>, started url: URL, fromQueue: Bool,
                                   url itemURL: (Item) -> URL?) -> Int? {
        guard fromQueue, let next = queue.nextIndex(), itemURL(queue.items[next]) == url else { return nil }
        return next
    }
}
