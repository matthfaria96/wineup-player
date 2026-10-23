import Foundation

/// Reserva de letras: catálogo do NetEase Cloud Music (sem chave; muitas letras sincronizadas).
/// Usado quando a fonte principal não tem a música.
public struct NetEaseLyricsClient: Sendable {
    private let fetcher: HTTPFetching
    private let base = "https://music.163.com/api"

    public init(fetcher: HTTPFetching = URLSessionFetcher()) { self.fetcher = fetcher }

    struct Song: Equatable {
        let id: Int
        let title: String
        let artist: String
        let album: String?
        let duration: Double?
    }

    /// Músicas parecidas (título + artista), as mais próximas primeiro.
    func songs(title: String, artist: String, duration: Double?) async throws -> [Song] {
        let term = [artist, TextMatch.cleanTitle(title)].filter { !$0.isEmpty }.joined(separator: " ")
        guard let url = FixerHTTP.url("\(base)/search/get", [("s", term), ("type", "1"), ("limit", "10")]) else { return [] }
        let json = try await FixerHTTP.json(fetcher, url, headers: Self.headers) as? [String: Any]
        let list = ((json?["result"] as? [String: Any])?["songs"] as? [[String: Any]] ?? []).compactMap(Self.song)
        return list.filter { Self.matches($0, title: title, artist: artist, duration: duration) }
            .sorted { Self.gap($0, duration) < Self.gap($1, duration) }
    }

    func lyrics(for song: Song) async throws -> LyricsCandidate? {
        guard let url = FixerHTTP.url("\(base)/song/lyric", [("id", String(song.id)), ("lv", "1"), ("kv", "1"), ("tv", "-1")])
        else { return nil }
        let json = try await FixerHTTP.json(fetcher, url, headers: Self.headers) as? [String: Any]
        let raw = (json?["lrc"] as? [String: Any])?["lyric"] as? String ?? ""
        let text = Self.clean(raw)
        guard !text.isEmpty else { return nil }
        let synced = LyricsInfo(text).isSynced && Self.hasRealTimes(text)
        return LyricsCandidate(id: "netease:\(song.id)", title: song.title, artist: song.artist, album: song.album,
                               duration: song.duration, synced: synced ? text : nil,
                               plain: synced ? LyricsInfo(text).lines.map(\.text).joined(separator: "\n") : Self.stripTimes(text),
                               instrumental: (json?["nolyric"] as? Bool) == true)
    }

    public func best(title: String, artist: String, album: String?, duration: Double?,
                     syncedOnly: Bool = false) async throws -> LyricsCandidate? {
        for song in try await songs(title: title, artist: artist, duration: duration).prefix(3) {
            if let found = try await lyrics(for: song), found.text != nil, !syncedOnly || found.isSynced { return found }
        }
        return nil
    }

    public func search(title: String, artist: String, duration: Double?) async throws -> [LyricsCandidate] {
        var out: [LyricsCandidate] = []
        for song in try await songs(title: title, artist: artist, duration: duration).prefix(4) {
            if let found = try? await lyrics(for: song), found.text != nil { out.append(found) }
        }
        return out
    }

    // MARK: Leitura

    static let headers = ["Referer": "https://music.163.com", "User-Agent": "Mozilla/5.0"]

    static func song(_ s: [String: Any]) -> Song? {
        guard let id = s["id"] as? Int, let name = s["name"] as? String else { return nil }
        let artists = (s["artists"] as? [[String: Any]] ?? []).compactMap { $0["name"] as? String }
        let ms = (s["duration"] as? Double) ?? (s["duration"] as? Int).map(Double.init)
        return Song(id: id, title: name, artist: artists.joined(separator: ", "),
                    album: (s["album"] as? [String: Any])?["name"] as? String, duration: ms.map { $0 / 1000 })
    }

    static func matches(_ s: Song, title: String, artist: String, duration: Double?) -> Bool {
        TextMatch.similarity(TextMatch.cleanTitle(s.title), TextMatch.cleanTitle(title)) > 0.8
            && (artist.isEmpty || TextMatch.similarity(s.artist, artist) > 0.6
                || TextMatch.normalize(s.artist).contains(TextMatch.normalize(artist)))
            && gap(s, duration) <= 5
    }

    static func gap(_ s: Song, _ duration: Double?) -> Double {
        guard let d = duration, let x = s.duration else { return 0 }
        return abs(d - x)
    }

    /// Tira as linhas de crédito ("作词 : …", "作曲 : …", "by: …") que o catálogo põe no início.
    static func clean(_ lrc: String) -> String {
        let credit = #"^\s*(\[[^\]]*\]\s*)*(作词|作曲|编曲|制作人|混音|母带|和声|吉他|贝斯|鼓|by)\s*[:：]"#
        return lrc.components(separatedBy: .newlines)
            .filter { $0.range(of: credit, options: [.regularExpression, .caseInsensitive]) == nil }
            .joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Letra "sincronizada" só com tudo em 00:00 não é sincronizada de verdade.
    static func hasRealTimes(_ lrc: String) -> Bool {
        (LyricsInfo(lrc).lines.compactMap(\.time).max() ?? 0) > 1
    }

    static func stripTimes(_ lrc: String) -> String {
        LyricsInfo(lrc).lines.map(\.text).joined(separator: "\n")
    }
}
