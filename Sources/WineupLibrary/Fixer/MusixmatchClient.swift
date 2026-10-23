import Foundation

/// Letras do Musixmatch com o token da conta do próprio usuário (o acesso anônimo é bloqueado:
/// devolve música e letra falsas). Só é consultado quando há token nas Opções.
public struct MusixmatchClient: Sendable {
    public enum Failure: Error, Equatable { case invalidToken }

    private let fetcher: HTTPFetching
    private let token: String

    public init(token: String, fetcher: HTTPFetching = URLSessionFetcher()) {
        self.token = token
        self.fetcher = fetcher
    }

    public func best(title: String, artist: String, album: String?, duration: Double?,
                     syncedOnly: Bool = false) async throws -> LyricsCandidate? {
        var q = [("format", "json"), ("namespace", "lyrics_richsynched"), ("subtitle_format", "lrc"),
                 ("app_id", "web-desktop-app-v1.0"), ("usertoken", token),
                 ("q_track", TextMatch.cleanTitle(title)), ("q_artist", artist)]
        if let album, !album.isEmpty { q.append(("q_album", album)) }
        if let duration, duration > 0 { q.append(("q_duration", String(Int(duration.rounded())))) }
        guard let url = FixerHTTP.url("https://apic-desktop.musixmatch.com/ws/1.1/macro.subtitles.get", q) else { return nil }
        let json = try await FixerHTTP.json(fetcher, url, headers: ["authority": "apic-desktop.musixmatch.com",
                                                                     "cookie": "AWSELBCORS=0; AWSELB=0"])
        let found = try Self.parse(json, title: title, artist: artist, duration: duration)
        guard let found, found.text != nil, !syncedOnly || found.isSynced else { return nil }
        return found
    }

    static func parse(_ json: Any, title: String, artist: String, duration: Double?) throws -> LyricsCandidate? {
        let message = (json as? [String: Any])?["message"] as? [String: Any]
        if (message?["header"] as? [String: Any])?["status_code"] as? Int == 401 { throw Failure.invalidToken }
        let calls = (message?["body"] as? [String: Any])?["macro_calls"] as? [String: Any] ?? [:]
        func body(_ key: String) -> [String: Any]? {
            ((calls[key] as? [String: Any])?["message"] as? [String: Any])?["body"] as? [String: Any]
        }
        guard let track = body("matcher.track.get")?["track"] as? [String: Any],
              let name = track["track_name"] as? String, let who = track["artist_name"] as? String else { return nil }
        // Resposta "isca" do acesso sem conta: música diferente da pedida. Só aceita se título e artista batem.
        guard TextMatch.similarity(TextMatch.cleanTitle(name), TextMatch.cleanTitle(title)) > 0.8,
              artist.isEmpty || TextMatch.similarity(who, artist) > 0.6 else { return nil }
        let length = (track["track_length"] as? Double) ?? (track["track_length"] as? Int).map(Double.init)
        if let d = duration, let l = length, abs(d - l) > 5 { return nil }
        let subtitle = ((body("track.subtitles.get")?["subtitle_list"] as? [[String: Any]])?.first?["subtitle"]
            as? [String: Any])?["subtitle_body"] as? String
        let plain = (body("track.lyrics.get")?["lyrics"] as? [String: Any])?["lyrics_body"] as? String
        let id = (track["track_id"] as? Int).map(String.init) ?? name
        return LyricsCandidate(id: "musixmatch:\(id)", title: name, artist: who,
                               album: track["album_name"] as? String, duration: length,
                               synced: subtitle?.isEmpty == false ? subtitle : nil,
                               plain: plain?.isEmpty == false ? plain : nil,
                               instrumental: (track["instrumental"] as? Int) == 1)
    }
}
