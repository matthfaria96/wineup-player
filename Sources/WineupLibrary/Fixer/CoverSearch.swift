import Foundation

/// Uma capa candidata na busca de capas (várias fontes).
public struct CoverCandidate: Sendable, Identifiable, Equatable {
    public enum Source: String, Sendable, CaseIterable { case musicBrainz = "MusicBrainz", iTunes = "iTunes" }

    public let id: String
    public let source: Source
    public let title: String
    public let artist: String
    public let date: String?
    public let detail: String?
    public let thumbURL: URL
    public let fullURL: URL
}

/// Procura capas de álbum por artista + álbum no Cover Art Archive (via MusicBrainz) e no iTunes.
public struct CoverSearch: Sendable {
    private let musicBrainz: MusicBrainzClient
    private let fetcher: HTTPFetching

    public init(musicBrainz: MusicBrainzClient = MusicBrainzClient(), fetcher: HTTPFetching = URLSessionFetcher()) {
        self.musicBrainz = musicBrainz
        self.fetcher = fetcher
    }

    public func search(artist: String, album: String, source: CoverCandidate.Source) async throws -> [CoverCandidate] {
        switch source {
        case .musicBrainz:
            guard OnlineServices.isOn(.metadata) else { return [] }
            return try await musicBrainz.searchReleases(artist: artist, album: album).compactMap { r in
                guard let thumb = URL(string: "https://coverartarchive.org/release/\(r.id)/front-250"),
                      let full = URL(string: "https://coverartarchive.org/release/\(r.id)/front-1200") else { return nil }
                return CoverCandidate(id: "mb:\(r.id)", source: .musicBrainz, title: r.title, artist: r.artist,
                                      date: r.date, detail: [r.format, r.country].compactMap { $0 }.joined(separator: " · "),
                                      thumbURL: thumb, fullURL: full)
            }
        case .iTunes:
            guard OnlineServices.isOn(.albumHint), let url = FixerHTTP.url("https://itunes.apple.com/search",
                                          [("term", "\(artist) \(album)"), ("entity", "album"), ("limit", "25")])
            else { return [] }
            let json = try await FixerHTTP.json(fetcher, url) as? [String: Any]
            return Self.iTunesAlbums(json?["results"] as? [[String: Any]] ?? [])
        }
    }

    static func iTunesAlbums(_ results: [[String: Any]]) -> [CoverCandidate] {
        results.compactMap { r in
            guard let art = r["artworkUrl100"] as? String, let title = r["collectionName"] as? String,
                  let thumb = URL(string: art.replacingOccurrences(of: "100x100bb", with: "250x250bb")),
                  let full = URL(string: art.replacingOccurrences(of: "100x100bb", with: "1000x1000bb")) else { return nil }
            let id = (r["collectionId"] as? Int).map(String.init) ?? art
            return CoverCandidate(id: "it:\(id)", source: .iTunes, title: title, artist: r["artistName"] as? String ?? "",
                                  date: (r["releaseDate"] as? String).map { String($0.prefix(10)) },
                                  detail: (r["trackCount"] as? Int).map { "\($0) faixas" }, thumbURL: thumb, fullURL: full)
        }
    }

    /// Baixa a imagem grande e confere que é JPEG/PNG.
    public func download(_ c: CoverCandidate) async throws -> CoverImage? {
        let (data, status) = try await fetcher.get(c.fullURL, headers: ["User-Agent": FixerHTTP.userAgent])
        guard (200..<300).contains(status), let mime = CoverArtClient.mimeType(of: data) else { return nil }
        return CoverImage(data: data, mimeType: mime)
    }
}
