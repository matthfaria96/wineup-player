import Foundation
import GRDB

/// Faixa da biblioteca pronta para a UI (valor imutável).
public struct LibraryTrack: Sendable, Equatable, Identifiable {
    public let id: Int64
    public let path: String
    public let title: String
    public let artist: String
    public let album: String
    public let genre: String?
    public let trackNumber: Int?
    public let discNumber: Int?
    public let duration: Double?
    public let status: FileStatus
    /// Faixa de CUE: arquivo de áudio real e trecho. `path` é a chave na biblioteca.
    public let mediaPath: String?
    public let start: Double?
    public let end: Double?

    /// Arquivo a tocar (o real, para faixas de CUE).
    public var url: URL { URL(fileURLWithPath: mediaPath ?? path) }

    /// SELECT base compartilhado por busca e navegação. O chamador acrescenta JOIN/WHERE/ORDER.
    static let baseSelect = """
        SELECT af.id AS id, af.path AS path, rec.title AS title,
               COALESCE(ar.name, 'Unknown Artist') AS artist, rel.title AS album,
               NULLIF(rt.genre, '') AS genre, rt.track_number AS track_number,
               rt.disc_number AS disc_number, COALESCE(rec.duration, af.duration) AS duration,
               af.status AS status, af.media_path AS media_path,
               af.segment_start AS segment_start, af.segment_end AS segment_end
        FROM audio_file af
        JOIN release_track rt ON rt.audio_file_id = af.id
        JOIN recording rec ON rec.id = rt.recording_id
        LEFT JOIN artist ar ON ar.id = rec.artist_id
        LEFT JOIN release rel ON rel.id = rt.release_id
        """

    static func make(_ row: Row) -> LibraryTrack {
        LibraryTrack(
            id: row["id"], path: row["path"], title: row["title"], artist: row["artist"],
            album: row["album"] ?? "Unknown Album", genre: row["genre"],
            trackNumber: row["track_number"], discNumber: row["disc_number"],
            duration: row["duration"],
            status: FileStatus(rawValue: row["status"] as String) ?? .present,
            mediaPath: row["media_path"], start: row["segment_start"], end: row["segment_end"])
    }
}
