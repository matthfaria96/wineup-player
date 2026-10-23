import Foundation

/// Busca de gravações no MusicBrainz (texto) e consulta por MBID (vinda do AcoustID).
public struct MusicBrainzClient: Sendable {
    private let fetcher: HTTPFetching
    private let pacer: RequestPacer
    private let base = "https://musicbrainz.org/ws/2"

    public init(fetcher: HTTPFetching = URLSessionFetcher(), minimumInterval: TimeInterval = 1.1) {
        self.fetcher = fetcher
        self.pacer = RequestPacer(interval: minimumInterval)
    }

    /// Candidatos para artista/título (e álbum, se houver), já com a confiança calculada.
    /// A busca por texto traz só parte dos lançamentos de cada gravação; se o melhor não for um álbum
    /// oficial de estúdio, uma segunda busca filtrada traz a versão de estúdio.
    public func search(title: String, artist: String, album: String?, duration: Double?) async throws -> [MatchCandidate] {
        var parts = ["recording:\"\(Self.escape(title))\""]
        if !artist.isEmpty { parts.append("artist:\"\(Self.escape(artist))\"") }
        if let album, !album.isEmpty { parts.append("release:\"\(Self.escape(album))\"") }
        let base = parts.joined(separator: " AND ")
        var out = try await query(base, title: title, artist: artist, album: album, duration: duration)
        if (out.first?.releaseRank ?? 1) > 0 {
            let studio = base + " AND status:official AND primarytype:album"
                + " AND NOT secondarytype:compilation AND NOT secondarytype:live"
            out += (try? await query(studio, title: title, artist: artist, album: album, duration: duration)) ?? []
        }
        return Self.dedupe(out.sorted(by: Self.better))
    }

    /// Maior confiança; empate: lançamento melhor e, depois, o mais antigo (edição original).
    static func better(_ a: MatchCandidate, _ b: MatchCandidate) -> Bool {
        if abs(a.confidence - b.confidence) > 0.001 { return a.confidence > b.confidence }
        if a.releaseRank != b.releaseRank { return a.releaseRank < b.releaseRank }
        return (a.year ?? "9999") < (b.year ?? "9999")
    }

    private func query(_ query: String, title: String, artist: String, album: String?,
                       duration: Double?) async throws -> [MatchCandidate] {
        guard let url = FixerHTTP.url("\(base)/recording", [("query", query), ("fmt", "json"), ("limit", "25")])
        else { return [] }
        await pacer.wait()
        let json = try await FixerHTTP.json(fetcher, url)
        let recordings = (json as? [String: Any])?["recordings"] as? [[String: Any]] ?? []
        var out = recordings.compactMap { Self.candidate(from: $0, preferAlbum: album, source: .musicBrainz) }
        for i in out.indices {
            out[i].confidence = TextMatch.confidence(
                title: title, artist: artist, duration: duration,
                candidateTitle: out[i].title, candidateArtist: out[i].artist, candidateDuration: out[i].duration,
                album: album, candidateAlbum: out[i].album)
            // Mesma música, versões diferentes: álbum oficial de estúdio vale mais que ao vivo/pirata/coletânea.
            out[i].confidence *= 1 - 0.02 * Double(min(out[i].releaseRank, 10))
        }
        return out
    }

    /// Gravação por MBID (inclui lançamentos, faixas e gêneros).
    public func recording(id: String, preferAlbum: String?) async throws -> MatchCandidate? {
        guard let url = FixerHTTP.url("\(base)/recording/\(id)",
                                      [("inc", "artist-credits+releases+media+release-groups+genres+tags"),
                                       ("fmt", "json")]) else { return nil }
        await pacer.wait()
        let json = try await FixerHTTP.json(fetcher, url)
        return (json as? [String: Any]).flatMap { Self.candidate(from: $0, preferAlbum: preferAlbum, source: .acoustID) }
    }

    /// GET respeitando o limite de 1 pedido por segundo do MusicBrainz.
    func getJSON(_ url: URL) async throws -> Any {
        await pacer.wait()
        return try await FixerHTTP.json(fetcher, url)
    }

    // MARK: Leitura do JSON

    static func candidate(from r: [String: Any], preferAlbum: String?, source: MatchCandidate.Source) -> MatchCandidate? {
        guard let id = r["id"] as? String, let title = r["title"] as? String else { return nil }
        let artist = credit(r["artist-credit"]) ?? ""
        let releases = r["releases"] as? [[String: Any]] ?? []
        let release = bestRelease(releases, preferAlbum: preferAlbum)
        let rank = release.map { penalty($0) } ?? 8
        let group = release?["release-group"] as? [String: Any]
        let medium = (release?["media"] as? [[String: Any]])?.first
        let track = ((medium?["track"] ?? medium?["tracks"]) as? [[String: Any]])?.first
        let date = (release?["date"] as? String) ?? (r["first-release-date"] as? String)
        return MatchCandidate(
            source: source, recordingID: id,
            releaseID: release?["id"] as? String, releaseGroupID: group?["id"] as? String,
            title: title, artist: artist,
            album: release?["title"] as? String,
            albumArtist: credit(release?["artist-credit"]) ?? (release == nil ? nil : artist),
            year: date.flatMap { $0.count >= 4 ? String($0.prefix(4)) : nil },
            trackNumber: (track?["number"] as? String).flatMap { Int($0) } ?? (track?["position"] as? Int),
            discNumber: medium?["position"] as? Int,
            genre: topGenre(r) ?? group.flatMap(topGenre),
            duration: (r["length"] as? Double).map { $0 / 1000 } ?? (r["length"] as? Int).map { Double($0) / 1000 },
            releaseRank: rank)
    }

    static func credit(_ value: Any?) -> String? {
        guard let parts = value as? [[String: Any]], !parts.isEmpty else { return nil }
        return parts.map { ($0["name"] as? String ?? "") + ($0["joinphrase"] as? String ?? "") }.joined()
    }

    /// Prefere o álbum que o arquivo já cita; senão um álbum oficial de estúdio. Entre iguais, o mais antigo
    /// (a edição original, não o relançamento).
    static func bestRelease(_ releases: [[String: Any]], preferAlbum: String?) -> [String: Any]? {
        func rank(_ r: [String: Any]) -> (Int, String) {
            (penalty(r), (r["date"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "9999")
        }
        if let preferAlbum, !preferAlbum.isEmpty {
            let same = releases.filter { TextMatch.similarity($0["title"] as? String ?? "", preferAlbum) > 0.8 }
            if let best = same.min(by: { rank($0) < rank($1) }) { return best }
        }
        return releases.min { rank($0) < rank($1) }
    }

    /// 0 = álbum oficial de estúdio; sobe para não oficial, single/EP, ao vivo, coletânea.
    static func penalty(_ r: [String: Any]) -> Int {
        let group = r["release-group"] as? [String: Any]
        var p = 0
        if (r["status"] as? String) != "Official" { p += 4 }
        if (group?["primary-type"] as? String) != "Album" { p += 2 }
        if !((group?["secondary-types"] as? [String]) ?? []).isEmpty { p += 3 }
        return p
    }

    static func topGenre(_ obj: [String: Any]) -> String? {
        let list = (obj["genres"] as? [[String: Any]]) ?? (obj["tags"] as? [[String: Any]]) ?? []
        let best = list.max { ($0["count"] as? Int ?? 0) < ($1["count"] as? Int ?? 0) }
        return (best?["name"] as? String).map { $0.prefix(1).uppercased() + $0.dropFirst() }
    }

    /// A busca devolve a mesma gravação várias vezes; fica a de maior confiança por título+artista+álbum.
    static func dedupe(_ list: [MatchCandidate]) -> [MatchCandidate] {
        var seen = Set<String>()
        return list.filter { c in
            seen.insert([c.title, c.artist, c.album ?? ""].map(TextMatch.normalize).joined(separator: "|")).inserted
        }
    }

    static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    }
}
