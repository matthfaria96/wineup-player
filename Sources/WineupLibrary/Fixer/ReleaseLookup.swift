import Foundation

/// Um lançamento (álbum, single, EP...) na lista de resultados da busca por álbum.
public struct ReleaseSummary: Sendable, Identifiable, Equatable {
    public let id: String
    public let score: Int
    public let title: String
    public let artist: String
    public let type: String
    public let trackCount: Int
    public let date: String?
    public let country: String?
    public let format: String?
    public let label: String?
    public let catalogNumber: String?
    public let releaseGroupID: String?

    public var year: String? { date.flatMap { $0.count >= 4 ? String($0.prefix(4)) : nil } }
}

/// Faixa de um lançamento.
public struct ReleaseTrack: Sendable, Identifiable, Equatable {
    public var id: String { "\(disc)-\(number)" }
    public let disc: Int
    public let number: Int
    public let title: String
    public let artist: String
    public let duration: Double?
    public let recordingID: String?
}

/// Lançamento completo, com as faixas de todos os discos.
public struct ReleaseDetail: Sendable, Equatable {
    public let id: String
    public let title: String
    public let artist: String
    public let date: String?
    public let genre: String?
    public let label: String?
    public let releaseGroupID: String?
    public let discCount: Int
    public let tracks: [ReleaseTrack]

    public var year: String? { date.flatMap { $0.count >= 4 ? String($0.prefix(4)) : nil } }

    /// Campos (vocabulário do TagSnapshot) que valem para todas as faixas do álbum.
    public var albumFields: [String: String] {
        var f: [String: String] = ["album": title, "albumArtist": artist]
        f["year"] = year
        f["genre"] = genre
        return f
    }

    /// Campos de uma faixa (título, artista, número, disco).
    public static func trackFields(_ t: ReleaseTrack) -> [String: String] {
        ["title": t.title, "artist": t.artist, "trackNumber": String(t.number), "discNumber": String(t.disc)]
    }
}

extension MusicBrainzClient {
    /// Busca de álbuns por artista + álbum (como a "Fonte de Etiquetas" do Mp3tag).
    public func searchReleases(artist: String, album: String) async throws -> [ReleaseSummary] {
        guard OnlineServices.isOn(.metadata) else { return [] }
        var parts: [String] = []
        if !album.isEmpty { parts.append("release:\"\(Self.escape(album))\"") }
        if !artist.isEmpty { parts.append("artist:\"\(Self.escape(artist))\"") }
        guard !parts.isEmpty,
              let url = FixerHTTP.url("https://musicbrainz.org/ws/2/release/",
                                      [("query", parts.joined(separator: " AND ")), ("fmt", "json"), ("limit", "50")])
        else { return [] }
        let json = try await getJSON(url)
        return ((json as? [String: Any])?["releases"] as? [[String: Any]] ?? []).compactMap(Self.summary)
    }

    /// Lançamento com faixas, artistas por faixa, gravadora e gênero.
    public func release(id: String) async throws -> ReleaseDetail? {
        guard let url = FixerHTTP.url("https://musicbrainz.org/ws/2/release/\(id)",
                                      [("inc", "artist-credits+recordings+release-groups+labels+genres"),
                                       ("fmt", "json")]) else { return nil }
        let json = try await getJSON(url)
        return (json as? [String: Any]).flatMap(Self.detail)
    }

    static func summary(_ r: [String: Any]) -> ReleaseSummary? {
        guard let id = r["id"] as? String, let title = r["title"] as? String else { return nil }
        let group = r["release-group"] as? [String: Any]
        let secondary = (group?["secondary-types"] as? [String]) ?? []
        let type = ([group?["primary-type"] as? String].compactMap { $0 } + secondary).joined(separator: " + ")
        let media = r["media"] as? [[String: Any]] ?? []
        let formats = Array(Set(media.compactMap { $0["format"] as? String })).sorted()
        let labelInfo = (r["label-info"] as? [[String: Any]])?.first
        return ReleaseSummary(
            id: id, score: r["score"] as? Int ?? 0, title: title, artist: credit(r["artist-credit"]) ?? "",
            type: type.isEmpty ? "—" : type,
            trackCount: r["track-count"] as? Int ?? media.reduce(0) { $0 + ($1["track-count"] as? Int ?? 0) },
            date: r["date"] as? String, country: r["country"] as? String,
            format: formats.isEmpty ? nil : (media.count > 1 ? "\(media.count)×" : "") + formats.joined(separator: ", "),
            label: (labelInfo?["label"] as? [String: Any])?["name"] as? String,
            catalogNumber: labelInfo?["catalog-number"] as? String,
            releaseGroupID: group?["id"] as? String)
    }

    static func detail(_ r: [String: Any]) -> ReleaseDetail? {
        guard let id = r["id"] as? String, let title = r["title"] as? String else { return nil }
        let albumArtist = credit(r["artist-credit"]) ?? ""
        let media = r["media"] as? [[String: Any]] ?? []
        var tracks: [ReleaseTrack] = []
        for (i, m) in media.enumerated() {
            let disc = m["position"] as? Int ?? i + 1
            for t in m["tracks"] as? [[String: Any]] ?? [] {
                let rec = t["recording"] as? [String: Any]
                let length = (t["length"] as? Double) ?? (t["length"] as? Int).map(Double.init)
                    ?? (rec?["length"] as? Double) ?? (rec?["length"] as? Int).map(Double.init)
                tracks.append(ReleaseTrack(
                    disc: disc, number: t["position"] as? Int ?? Int(t["number"] as? String ?? "") ?? tracks.count + 1,
                    title: t["title"] as? String ?? rec?["title"] as? String ?? "",
                    artist: credit(t["artist-credit"]) ?? credit(rec?["artist-credit"]) ?? albumArtist,
                    duration: length.map { $0 / 1000 }, recordingID: rec?["id"] as? String))
            }
        }
        let group = r["release-group"] as? [String: Any]
        let label = ((r["label-info"] as? [[String: Any]])?.first?["label"] as? [String: Any])?["name"] as? String
        return ReleaseDetail(id: id, title: title, artist: albumArtist, date: r["date"] as? String,
                             genre: topGenre(r) ?? group.flatMap(topGenre), label: label,
                             releaseGroupID: group?["id"] as? String, discCount: max(media.count, 1), tracks: tracks)
    }
}

/// Liga cada arquivo a uma faixa do álbum (título, duração e número), sem repetir faixa.
public enum TrackMatcher {
    public static func score(_ file: FixerFile, _ track: ReleaseTrack, discCount: Int) -> Double {
        let fileTitle = file.value("title").isEmpty ? FilenameGuess.parse(file.url).title : file.value("title")
        var s = 0.6 * TextMatch.similarity(TextMatch.cleanTitle(fileTitle), TextMatch.cleanTitle(track.title))
        if let d = file.duration, let t = track.duration {
            let diff = abs(d - t)
            s += 0.25 * (diff <= 2 ? 1 : diff >= 20 ? 0 : 1 - (diff - 2) / 18)
        }
        let number = Int(file.value("trackNumber")) ?? FilenameGuess.parse(file.url).trackNumber
        let disc = Int(file.value("discNumber")) ?? 1
        if number == track.number && (discCount == 1 || disc == track.disc) { s += 0.15 }
        return s
    }

    /// Arquivo → índice da faixa (nil = sem par). Melhores pares primeiro; abaixo de 0,45 fica sem par.
    public static func match(files: [FixerFile], release: ReleaseDetail) -> [String: Int] {
        var pairs: [(file: String, track: Int, score: Double)] = []
        for f in files {
            for (i, t) in release.tracks.enumerated() {
                pairs.append((f.id, i, score(f, t, discCount: release.discCount)))
            }
        }
        var out: [String: Int] = [:]
        var used = Set<Int>()
        for p in pairs.sorted(by: { $0.score > $1.score }) where p.score >= 0.45 {
            guard out[p.file] == nil, !used.contains(p.track) else { continue }
            out[p.file] = p.track
            used.insert(p.track)
        }
        return out
    }
}
