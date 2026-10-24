import Foundation

public enum TrackList {
    public static func removing(_ id: TrackID, from tracks: [Track]) -> [Track] {
        tracks.filter { $0.id != id }
    }

    /// Faixas cujo "Artista - Título" contém o texto (sem diferenciar maiúsculas), na ordem da lista.
    public static func matching(_ text: String, in tracks: [Track]) -> [Track] {
        let needle = text.trimmingCharacters(in: .whitespaces)
        guard !needle.isEmpty else { return [] }
        return tracks.filter { $0.displayName.localizedCaseInsensitiveContains(needle) }
    }
}

/// Tamanho dos lotes ao abrir muitos arquivos: o primeiro é pequeno (a lista aparece e toca logo);
/// os seguintes dobram até um teto (menos redesenhos da lista).
public enum LoadBatches {
    public static func size(afterDelivered delivered: Int, first: Int = 100, limit: Int = 2000) -> Int {
        delivered <= 0 ? first : min(limit, max(first, delivered))
    }
}
