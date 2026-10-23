import Foundation

/// Letras do LRCLIB (sincronizadas quando houver). Sem chave de API.
public struct LRCLibClient: Sendable {
    private let fetcher: HTTPFetching
    private let base = "https://lrclib.net/api"

    public init(fetcher: HTTPFetching = URLSessionFetcher()) { self.fetcher = fetcher }

    /// Correspondência exata (artista, título, álbum, duração); nil se o LRCLIB não tem.
    public func exact(title: String, artist: String, album: String?, duration: Double?) async throws -> LyricsCandidate? {
        let title = TextMatch.cleanTitle(title)
        var q = [("track_name", title), ("artist_name", artist)]
        if let album, !album.isEmpty { q.append(("album_name", album)) }
        if let duration, duration > 0 { q.append(("duration", String(Int(duration.rounded())))) }
        guard let url = FixerHTTP.url("\(base)/get", q) else { return nil }
        do {
            let json = try await FixerHTTP.json(fetcher, url, headers: Self.headers)
            return (json as? [String: Any]).flatMap(Self.candidate)
        } catch FixerNetworkError.notFound {
            return nil
        }
    }

    /// Lista para escolha manual, sincronizadas e de duração próxima primeiro.
    public func search(title: String, artist: String, duration: Double?) async throws -> [LyricsCandidate] {
        let title = TextMatch.cleanTitle(title)
        var q = [("track_name", title)]
        if !artist.isEmpty { q.append(("artist_name", artist)) }
        guard let url = FixerHTTP.url("\(base)/search", q) else { return [] }
        let json = try await FixerHTTP.json(fetcher, url, headers: Self.headers)
        let list = (json as? [[String: Any]] ?? []).compactMap(Self.candidate)
        return list.sorted { a, b in
            if a.isSynced != b.isSynced { return a.isSynced }
            return Self.gap(a, duration) < Self.gap(b, duration)
        }
    }

    /// Melhor letra: exata (com álbum, depois sem); senão a da busca com título e artista iguais e
    /// duração até 5 s de diferença. `syncedOnly` para quem já tem letra estática.
    public func best(title: String, artist: String, album: String?, duration: Double?,
                     syncedOnly: Bool = false) async throws -> LyricsCandidate? {
        func ok(_ c: LyricsCandidate?) -> Bool { c?.text != nil && (!syncedOnly || c?.isSynced == true) }
        let hit = try await exact(title: title, artist: artist, album: album, duration: duration)
        if ok(hit) { return hit }
        if album != nil, let noAlbum = try await exact(title: title, artist: artist, album: nil, duration: duration),
           ok(noAlbum) { return noAlbum }
        let clean = TextMatch.cleanTitle(title)
        return try await search(title: title, artist: artist, duration: duration).first { c in
            ok(c) && Self.gap(c, duration) <= 5
                && TextMatch.similarity(TextMatch.cleanTitle(c.title), clean) > 0.8
                && (artist.isEmpty || TextMatch.similarity(c.artist, artist) > 0.7)
        }
    }

    static let headers = ["Lrclib-Client": FixerHTTP.userAgent]

    static func gap(_ c: LyricsCandidate, _ duration: Double?) -> Double {
        guard let d = duration, let x = c.duration else { return 0 }
        return abs(d - x)
    }

    static func candidate(_ o: [String: Any]) -> LyricsCandidate? {
        guard let id = o["id"] as? Int else { return nil }
        return LyricsCandidate(
            id: "lrclib:\(id)", title: o["trackName"] as? String ?? "", artist: o["artistName"] as? String ?? "",
            album: o["albumName"] as? String, duration: (o["duration"] as? Double) ?? (o["duration"] as? Int).map(Double.init),
            synced: o["syncedLyrics"] as? String, plain: o["plainLyrics"] as? String,
            instrumental: o["instrumental"] as? Bool ?? false)
    }
}
