import Foundation
import GRDB

public struct ScannedTags: Sendable, Equatable {
    public var title: String?
    public var artist: String?
    public var albumArtist: String?
    public var album: String?
    public var genre: String?
    public var year: String?
    public var releaseType: String?
    public var trackNumber: Int?
    public var discNumber: Int?
    public var duration: Double?
    public var hasEmbeddedArtwork: Bool
    public var lyrics: String?

    public init(title: String? = nil, artist: String? = nil, albumArtist: String? = nil,
                album: String? = nil, genre: String? = nil, year: String? = nil,
                releaseType: String? = nil, trackNumber: Int? = nil, discNumber: Int? = nil,
                duration: Double? = nil, hasEmbeddedArtwork: Bool = false, lyrics: String? = nil) {
        self.title = title; self.artist = artist; self.albumArtist = albumArtist
        self.album = album; self.genre = genre; self.year = year; self.releaseType = releaseType
        self.trackNumber = trackNumber; self.discNumber = discNumber; self.duration = duration
        self.hasEmbeddedArtwork = hasEmbeddedArtwork; self.lyrics = lyrics
    }
}

public enum CatalogWriter {
    static func sortKey(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
    }

    private static func clean(_ s: String?) -> String? {
        guard let t = s?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty else { return nil }
        return t
    }

    private static func artistID(_ db: Database, name: String?) throws -> Int64 {
        let display = clean(name) ?? "Unknown Artist"
        let key = sortKey(display)
        if let id = try Int64.fetchOne(db, sql: "SELECT id FROM artist WHERE sort_key = ?", arguments: [key]) {
            return id
        }
        var rec = ArtistRecord(name: display, sortKey: key)
        try rec.insert(db)
        return rec.id!
    }

    /// Chamar dentro de uma transação aberta pelo chamador.
    public static func ingest(_ db: Database, audioFileID: Int64, tags: ScannedTags,
                              fallbackTitle: String) throws {
        let title = clean(tags.title) ?? fallbackTitle
        let artistName = clean(tags.artist) ?? clean(tags.albumArtist)
        let trackArtist = try artistID(db, name: artistName)
        let albumArtist = try artistID(db, name: clean(tags.albumArtist) ?? artistName)
        let albumTitle = clean(tags.album) ?? "Unknown Album"
        let kind = ReleaseKind.resolve(tagValue: tags.releaseType)
        let kindSource = tags.releaseType == nil ? "inferred" : "tag"

        let releaseID: Int64
        if let id = try Int64.fetchOne(
            db, sql: "SELECT id FROM release WHERE title = ? AND album_artist_id = ?",
            arguments: [albumTitle, albumArtist]) {
            releaseID = id
        } else {
            var rel = ReleaseRecord(title: albumTitle, albumArtistID: albumArtist,
                                    year: clean(tags.year), kind: kind.rawValue, kindSource: kindSource)
            try rel.insert(db)
            releaseID = rel.id!
        }

        let existing = try ReleaseTrackRecord.filter(Column("audio_file_id") == audioFileID).fetchOne(db)
        var recordingID: Int64
        if let rid = existing?.recordingID {
            recordingID = rid
            try db.execute(sql: "UPDATE recording SET title = ?, artist_id = ?, duration = ? WHERE id = ?",
                           arguments: [title, trackArtist, tags.duration, rid])
        } else {
            var rec = RecordingRecord(title: title, artistID: trackArtist, duration: tags.duration)
            try rec.insert(db)
            recordingID = rec.id!
        }
        let genre = clean(tags.genre)
        if var rt = existing {
            rt.releaseID = releaseID; rt.recordingID = recordingID
            rt.discNumber = tags.discNumber; rt.trackNumber = tags.trackNumber; rt.genre = genre
            try rt.update(db)
        } else {
            var rt = ReleaseTrackRecord(releaseID: releaseID, recordingID: recordingID,
                                        audioFileID: audioFileID, discNumber: tags.discNumber,
                                        trackNumber: tags.trackNumber, genre: genre)
            try rt.insert(db)
        }

        try db.execute(sql: "DELETE FROM lyrics WHERE audio_file_id = ? AND source = 'embedded'",
                       arguments: [audioFileID])
        if let text = clean(tags.lyrics) {
            var l = LyricsRecord(recordingID: recordingID, audioFileID: audioFileID,
                                 source: "embedded", synced: false, text: text)
            try l.insert(db)
        }

        let artistDisplay = try String.fetchOne(db, sql: "SELECT name FROM artist WHERE id = ?",
                                                arguments: [trackArtist]) ?? ""
        try db.execute(sql: "DELETE FROM track_fts WHERE rowid = ?", arguments: [audioFileID])
        try db.execute(sql: "INSERT INTO track_fts(rowid,title,artist,album,genre) VALUES (?,?,?,?,?)",
                       arguments: [audioFileID, title, artistDisplay, albumTitle, genre ?? ""])
    }

    /// Tira o item da busca sem apagar o registro (itens `missing` nunca são apagados).
    public static func removeFromIndex(_ db: Database, audioFileID: Int64) throws {
        try db.execute(sql: "DELETE FROM track_fts WHERE rowid = ?", arguments: [audioFileID])
    }
}
