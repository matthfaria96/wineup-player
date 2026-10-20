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

    public var url: URL { URL(fileURLWithPath: path) }

    /// SELECT base compartilhado por busca e navegação. O chamador acrescenta JOIN/WHERE/ORDER.
    static let baseSelect = """
        SELECT af.id AS id, af.path AS path, rec.title AS title,
               COALESCE(ar.name, 'Unknown Artist') AS artist, rel.title AS album,
               NULLIF(rt.genre, '') AS genre, rt.track_number AS track_number,
               rt.disc_number AS disc_number, COALESCE(rec.duration, af.duration) AS duration,
               af.status AS status
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
            status: FileStatus(rawValue: row["status"] as String) ?? .present)
    }
}
