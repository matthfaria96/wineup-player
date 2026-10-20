import AppKit
import WineupCore

/// Botão "Metadados": por enquanto mostra o que falta nas faixas da lista atual.
/// A correção guiada (Library Fixer) usa este ponto de entrada.
enum MetadataSummary {
    static func show(state: PlayerState) {
        let tracks = state.tracks.filter { $0.url != nil }
        let noArtist = tracks.filter { $0.artist.isEmpty || $0.artist == "Unknown Artist" || $0.artist == "Desconhecido" }.count
        let noAlbum = tracks.filter { ($0.album ?? "").isEmpty || $0.album == "Unknown Album" }.count
        let alert = NSAlert()
        alert.messageText = "Metadados"
        alert.informativeText = tracks.isEmpty
            ? "Abra uma pasta de músicas para verificar os metadados."
            : "Na lista atual (\(tracks.count) faixas):\n• \(noArtist) sem artista\n• \(noAlbum) sem álbum\n\nA correção guiada, com prévia e desfazer, está chegando."
        alert.runModal()
    }
}
