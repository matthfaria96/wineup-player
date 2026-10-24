import Foundation
import GRDB

public enum FileStatus: String, Sendable, Codable { case present, missing }

public enum ReleaseKind: String, Sendable, Codable {
    case album, single, ep, compilation, unknown

    /// Nunca infere "single" pelo número de faixas: sem tag, é `.unknown`.
    public static func resolve(tagValue: String?) -> ReleaseKind {
        guard let raw = tagValue?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              let kind = ReleaseKind(rawValue: raw) else { return .unknown }
        return kind
    }
}

public struct LibraryRootRecord: Codable, FetchableRecord, MutablePersistableRecord, Sendable {
    public static let databaseTableName = "library_root"
    public var id: Int64?
    public var uuid: String
    public var path: String
    public var volumeUUID: String?
    public var online: Bool
    public var addedAt: Date
    public var lastScanAt: Date?
    public init(id: Int64? = nil, uuid: String, path: String, volumeUUID: String? = nil,
                online: Bool = true, addedAt: Date = Date(), lastScanAt: Date? = nil) {
        self.id = id; self.uuid = uuid; self.path = path; self.volumeUUID = volumeUUID
        self.online = online; self.addedAt = addedAt; self.lastScanAt = lastScanAt
    }
    enum CodingKeys: String, CodingKey {
        case id, uuid, path, online
        case volumeUUID = "volume_uuid", addedAt = "added_at", lastScanAt = "last_scan_at"
    }
    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}

public struct AudioFileRecord: Codable, FetchableRecord, MutablePersistableRecord, Sendable {
    public static let databaseTableName = "audio_file"
    public var id: Int64?
    public var rootID: Int64
    public var path: String
    public var volumeUUID: String?
    public var inode: Int64?
    public var size: Int64
    public var mtimeNs: Int64
    public var contentHash: Data?
    public var status: String
    public var missingSince: Date?
    public var lastSeenAt: Date?
    public var format: String?
    public var duration: Double?
    public var readError: String?
    public init(id: Int64? = nil, rootID: Int64, path: String, volumeUUID: String? = nil,
                inode: Int64? = nil, size: Int64 = 0, mtimeNs: Int64 = 0, contentHash: Data? = nil,
                status: String = FileStatus.present.rawValue, missingSince: Date? = nil,
                lastSeenAt: Date? = nil, format: String? = nil, duration: Double? = nil,
                readError: String? = nil) {
        self.id = id; self.rootID = rootID; self.path = path; self.volumeUUID = volumeUUID
        self.inode = inode; self.size = size; self.mtimeNs = mtimeNs; self.contentHash = contentHash
        self.status = status; self.missingSince = missingSince; self.lastSeenAt = lastSeenAt
        self.format = format; self.duration = duration; self.readError = readError
    }
    enum CodingKeys: String, CodingKey {
        case id, path, inode, size, status, format, duration
        case rootID = "root_id", volumeUUID = "volume_uuid", mtimeNs = "mtime_ns"
        case contentHash = "content_hash", missingSince = "missing_since"
        case lastSeenAt = "last_seen_at", readError = "read_error"
    }
    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}

public struct ArtistRecord: Codable, FetchableRecord, MutablePersistableRecord, Sendable {
    public static let databaseTableName = "artist"
    public var id: Int64?
    public var name: String
    public var sortKey: String
    public init(id: Int64? = nil, name: String, sortKey: String) {
        self.id = id; self.name = name; self.sortKey = sortKey
    }
    enum CodingKeys: String, CodingKey { case id, name; case sortKey = "sort_key" }
    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}

public struct ReleaseRecord: Codable, FetchableRecord, MutablePersistableRecord, Sendable {
    public static let databaseTableName = "release"
    public var id: Int64?
    public var title: String
    public var albumArtistID: Int64?
    public var year: String?
    public var kind: String
    public var kindSource: String
    public init(id: Int64? = nil, title: String, albumArtistID: Int64? = nil, year: String? = nil,
                kind: String = ReleaseKind.unknown.rawValue, kindSource: String = "inferred") {
        self.id = id; self.title = title; self.albumArtistID = albumArtistID; self.year = year
        self.kind = kind; self.kindSource = kindSource
    }
    enum CodingKeys: String, CodingKey {
        case id, title, year, kind
        case albumArtistID = "album_artist_id", kindSource = "kind_source"
    }
    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}

public struct RecordingRecord: Codable, FetchableRecord, MutablePersistableRecord, Sendable {
    public static let databaseTableName = "recording"
    public var id: Int64?
    public var title: String
    public var artistID: Int64?
    public var duration: Double?
    public init(id: Int64? = nil, title: String, artistID: Int64? = nil, duration: Double? = nil) {
        self.id = id; self.title = title; self.artistID = artistID; self.duration = duration
    }
    enum CodingKeys: String, CodingKey { case id, title, duration; case artistID = "artist_id" }
    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}

public struct ReleaseTrackRecord: Codable, FetchableRecord, MutablePersistableRecord, Sendable {
    public static let databaseTableName = "release_track"
    public var id: Int64?
    public var releaseID: Int64?
    public var recordingID: Int64
    public var audioFileID: Int64
    public var discNumber: Int?
    public var trackNumber: Int?
    public var genre: String?
    public init(id: Int64? = nil, releaseID: Int64?, recordingID: Int64, audioFileID: Int64,
                discNumber: Int? = nil, trackNumber: Int? = nil, genre: String? = nil) {
        self.id = id; self.releaseID = releaseID; self.recordingID = recordingID
        self.audioFileID = audioFileID; self.discNumber = discNumber
        self.trackNumber = trackNumber; self.genre = genre
    }
    enum CodingKeys: String, CodingKey {
        case id, genre
        case releaseID = "release_id", recordingID = "recording_id", audioFileID = "audio_file_id"
        case discNumber = "disc_number", trackNumber = "track_number"
    }
    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}

public struct LyricsRecord: Codable, FetchableRecord, MutablePersistableRecord, Sendable {
    public static let databaseTableName = "lyrics"
    public var id: Int64?
    public var recordingID: Int64?
    public var audioFileID: Int64?
    public var source: String
    public var synced: Bool
    public var text: String?
    public init(id: Int64? = nil, recordingID: Int64? = nil, audioFileID: Int64? = nil,
                source: String, synced: Bool = false, text: String? = nil) {
        self.id = id; self.recordingID = recordingID; self.audioFileID = audioFileID
        self.source = source; self.synced = synced; self.text = text
    }
    enum CodingKeys: String, CodingKey {
        case id, source, synced, text
        case recordingID = "recording_id", audioFileID = "audio_file_id"
    }
    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}

public struct JournalRecord: Codable, FetchableRecord, PersistableRecord, Sendable {
    public static let databaseTableName = "journal"
    public var id: String
    public var audioFileID: Int64?
    public var path: String
    public var backupPath: String?
    public var diffsJSON: String
    public var status: String
    public var afterInode: Int64?
    public var afterSize: Int64?
    public var afterMtimeNs: Int64?
    public var createdAt: Date
    public var undoneAt: Date?
    public init(id: String = UUID().uuidString, audioFileID: Int64?, path: String,
                backupPath: String? = nil, diffsJSON: String, status: String,
                afterInode: Int64? = nil, afterSize: Int64? = nil, afterMtimeNs: Int64? = nil,
                createdAt: Date = Date(), undoneAt: Date? = nil) {
        self.id = id; self.audioFileID = audioFileID; self.path = path; self.backupPath = backupPath
        self.diffsJSON = diffsJSON; self.status = status; self.afterInode = afterInode
        self.afterSize = afterSize; self.afterMtimeNs = afterMtimeNs
        self.createdAt = createdAt; self.undoneAt = undoneAt
    }
    enum CodingKeys: String, CodingKey {
        case id, path, status
        case audioFileID = "audio_file_id", backupPath = "backup_path", diffsJSON = "diffs_json"
        case afterInode = "after_inode", afterSize = "after_size", afterMtimeNs = "after_mtime_ns"
        case createdAt = "created_at", undoneAt = "undone_at"
    }
}

public struct TagSnapshotRecord: Codable, FetchableRecord, MutablePersistableRecord, Sendable {
    public static let databaseTableName = "tag_snapshot"
    public var id: Int64?
    public var journalID: String
    public var kind: String
    public var json: String
    public init(id: Int64? = nil, journalID: String, kind: String, json: String) {
        self.id = id; self.journalID = journalID; self.kind = kind; self.json = json
    }
    enum CodingKeys: String, CodingKey { case id, kind, json; case journalID = "journal_id" }
    public mutating func didInsert(_ inserted: InsertionSuccess) { id = inserted.rowID }
}
