import Foundation

/// Dica de álbum pela API de busca do iTunes (sem chave). Só serve para orientar a busca no MusicBrainz
/// quando o arquivo não diz o álbum: a busca por texto do MusicBrainz devolve centenas de gravações
/// ao vivo/piratas com a mesma pontuação para músicas conhecidas.
public struct ITunesHintClient: Sendable {
    public struct Hint: Sendable, Equatable {
        public let album: String
        public let genre: String?
    }

    private let fetcher: HTTPFetching

    public init(fetcher: HTTPFetching = URLSessionFetcher()) { self.fetcher = fetcher }

    public func albumHint(title: String, artist: String, duration: Double?) async throws -> Hint? {
        guard !title.isEmpty, !artist.isEmpty,
              let url = FixerHTTP.url("https://itunes.apple.com/search",
                                      [("term", "\(artist) \(title)"), ("entity", "song"), ("limit", "15")])
        else { return nil }
        let json = try await FixerHTTP.json(fetcher, url) as? [String: Any]
        return Self.best(json?["results"] as? [[String: Any]] ?? [], title: title, artist: artist, duration: duration)
    }

    /// A faixa mais parecida, preferindo o álbum do próprio artista (não coletânea, não ao vivo).
    static func best(_ results: [[String: Any]], title: String, artist: String, duration: Double?) -> Hint? {
        func score(_ r: [String: Any]) -> Double {
            var s = TextMatch.confidence(
                title: title, artist: artist, duration: duration,
                candidateTitle: r["trackName"] as? String ?? "", candidateArtist: r["artistName"] as? String ?? "",
                candidateDuration: (r["trackTimeMillis"] as? Double).map { $0 / 1000 })
            let album = (r["collectionName"] as? String ?? "").lowercased()
            if (r["collectionArtistName"] as? String) == "Various Artists" { s -= 0.15 }
            if ["live", "ao vivo", "greatest hits", "best of", "collection"].contains(where: album.contains) { s -= 0.1 }
            if album.hasSuffix(" - single") || album.hasSuffix(" - ep") { s -= 0.05 }
            return s
        }
        guard let top = results.max(by: { score($0) < score($1) }), score(top) >= 0.75,
              let album = top["collectionName"] as? String else { return nil }
        let clean = album.replacingOccurrences(of: #"\s*\((Remastered|Deluxe|Expanded)[^)]*\)"#, with: "",
                                               options: [.regularExpression, .caseInsensitive])
        return Hint(album: clean, genre: top["primaryGenreName"] as? String)
    }
}
