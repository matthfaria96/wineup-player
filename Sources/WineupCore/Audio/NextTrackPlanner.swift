import Foundation

public enum NextTrackPlanner {
    /// Vizinha seguinte, sem wrap (repetir/embaralhar é da Fase 4). Fim da lista ou id ausente -> nil.
    public static func next<T: Identifiable>(after id: T.ID, in items: [T]) -> T? {
        guard let index = items.firstIndex(where: { $0.id == id }), index + 1 < items.count else { return nil }
        return items[index + 1]
    }
}
