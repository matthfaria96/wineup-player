import Foundation

/// Ordem de "Reproduzir tudo" na página do artista.
public enum ArtistOrder: String, CaseIterable, Sendable, Identifiable {
    case byAlbum, chronological, alphabetical

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .byAlbum: "Por álbum"
        case .chronological: "Cronológica"
        case .alphabetical: "Alfabética"
        }
    }
}

/// Monta a fila do artista: ordem escolhida e, se pedido, sem repetir a mesma gravação
/// lançada em single e em álbum (fica a do álbum; remix e ao vivo são músicas diferentes).
public enum ArtistQueue {
    public static func make(_ tracks: [Track], order: ArtistOrder, dedupe: Bool) -> [Track] {
        let ordered = sort(tracks, order)
        return dedupe ? removeRepeats(ordered) : ordered
    }

    static func sort(_ tracks: [Track], _ order: ArtistOrder) -> [Track] {
        let indexed = Array(tracks.enumerated())
        switch order {
        case .byAlbum:
            // Álbuns em ordem alfabética; dentro do álbum, a ordem original (disco/faixa).
            return indexed.sorted { a, b in
                let x = albumKey(a.element), y = albumKey(b.element)
                return x == y ? a.offset < b.offset : x.localizedStandardCompare(y) == .orderedAscending
            }.map(\.element)
        case .chronological:
            return indexed.sorted { a, b in
                let x = year(a.element), y = year(b.element)
                if x != y { return x < y }
                let ax = albumKey(a.element), ay = albumKey(b.element)
                return ax == ay ? a.offset < b.offset : ax.localizedStandardCompare(ay) == .orderedAscending
            }.map(\.element)
        case .alphabetical:
            return tracks.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        }
    }

    /// Mesma gravação = mesmo título normalizado e duração até 3 s; prefere a que está num álbum com mais faixas.
    static func removeRepeats(_ tracks: [Track]) -> [Track] {
        let albumSizes = Dictionary(grouping: tracks, by: albumKey).mapValues(\.count)
        var keep: [String: Track] = [:]
        var order: [String] = []
        for t in tracks {
            let key = recordingKey(t)
            if let existing = keep[key], abs(existing.duration - t.duration) <= 3 {
                if (albumSizes[albumKey(t)] ?? 0) > (albumSizes[albumKey(existing)] ?? 0) { keep[key] = t }
            } else if keep[key] == nil {
                keep[key] = t
                order.append(key)
            } else {
                // Mesmo título, duração bem diferente: outra versão, entra também.
                let alt = key + "#\(t.duration)"
                keep[alt] = t
                order.append(alt)
            }
        }
        return order.compactMap { keep[$0] }
    }

    static func albumKey(_ t: Track) -> String { (t.album ?? "").trimmingCharacters(in: .whitespaces).lowercased() }

    static func year(_ t: Track) -> String {
        guard let y = t.year?.prefix(4), y.count == 4 else { return "9999" }
        return String(y)
    }

    static func recordingKey(_ t: Track) -> String {
        t.title.lowercased().unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }.map(String.init).joined()
    }
}
