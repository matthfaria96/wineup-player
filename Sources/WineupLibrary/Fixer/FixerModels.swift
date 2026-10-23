import Foundation

/// O que falta (ou sobra) num arquivo, segundo a análise da pasta.
public enum FixerIssue: String, Sendable, CaseIterable, Codable {
    case missingTitle, missingArtist, missingAlbum, missingYear, missingTrack, missingGenre
    case missingCover, missingLyrics, duplicate

    public var label: String {
        switch self {
        case .missingTitle: "Sem título"
        case .missingArtist: "Sem artista"
        case .missingAlbum: "Sem álbum"
        case .missingYear: "Sem ano"
        case .missingTrack: "Sem nº da faixa"
        case .missingGenre: "Sem gênero"
        case .missingCover: "Sem capa"
        case .missingLyrics: "Sem letra"
        case .duplicate: "Duplicada"
        }
    }

    /// Itens que a busca automática consegue resolver (duplicadas não).
    public var isFixable: Bool { self != .duplicate }
}

/// Um arquivo de áudio da pasta, como está no disco.
public struct FixerFile: Sendable, Identifiable, Equatable {
    public var id: String { url.path }
    public let url: URL
    public var fields: [String: String]
    public var pictureCount: Int
    public var coverBytes: Int
    public var duration: Double?
    public var size: Int64
    public var hasSidecarLyrics: Bool
    public var hasEmbeddedLyrics: Bool
    /// true = letra com marcas de tempo, false = estática, nil = sem letra.
    public var lyricsSynced: Bool?
    public var isWritable: Bool
    public var issues: Set<FixerIssue>
    public var duplicateGroup: Int?

    public init(url: URL, fields: [String: String] = [:], pictureCount: Int = 0, coverBytes: Int = 0,
                duration: Double? = nil, size: Int64 = 0, hasSidecarLyrics: Bool = false,
                hasEmbeddedLyrics: Bool = false, isWritable: Bool = true,
                issues: Set<FixerIssue> = [], duplicateGroup: Int? = nil) {
        self.url = url; self.fields = fields; self.pictureCount = pictureCount; self.coverBytes = coverBytes
        self.duration = duration; self.size = size; self.hasSidecarLyrics = hasSidecarLyrics
        self.hasEmbeddedLyrics = hasEmbeddedLyrics; self.isWritable = isWritable
        self.issues = issues; self.duplicateGroup = duplicateGroup
    }

    public var lyricsURL: URL { url.deletingPathExtension().appendingPathExtension("lrc") }
    public var hasCover: Bool { pictureCount > 0 }
    public var hasLyrics: Bool { hasSidecarLyrics || hasEmbeddedLyrics }
    public func value(_ field: String) -> String { fields[field] ?? "" }
}

/// Resultado de uma base de metadados para uma faixa.
public struct MatchCandidate: Sendable, Identifiable, Equatable {
    public enum Source: String, Sendable { case musicBrainz = "MusicBrainz", acoustID = "AcoustID" }

    public var id: String { "\(recordingID)/\(releaseID ?? "-")" }
    public var source: Source
    public var recordingID: String
    public var releaseID: String?
    public var releaseGroupID: String?
    public var title: String
    public var artist: String
    public var album: String?
    public var albumArtist: String?
    public var year: String?
    public var trackNumber: Int?
    public var discNumber: Int?
    public var genre: String?
    public var duration: Double?
    /// 0...1, calculada contra as tags atuais (ou o nome do arquivo).
    public var confidence: Double
    /// Qualidade do lançamento escolhido (0 = álbum oficial de estúdio; maior = ao vivo, pirata, coletânea).
    public var releaseRank: Int

    public init(source: Source, recordingID: String, releaseID: String? = nil, releaseGroupID: String? = nil,
                title: String, artist: String, album: String? = nil, albumArtist: String? = nil,
                year: String? = nil, trackNumber: Int? = nil, discNumber: Int? = nil, genre: String? = nil,
                duration: Double? = nil, confidence: Double = 0, releaseRank: Int = 0) {
        self.source = source; self.recordingID = recordingID; self.releaseID = releaseID
        self.releaseGroupID = releaseGroupID; self.title = title; self.artist = artist; self.album = album
        self.albumArtist = albumArtist; self.year = year; self.trackNumber = trackNumber
        self.discNumber = discNumber; self.genre = genre; self.duration = duration; self.confidence = confidence
        self.releaseRank = releaseRank
    }

    /// Campos no vocabulário do TagSnapshot.
    public var fields: [String: String] {
        var f: [String: String] = ["title": title, "artist": artist]
        f["album"] = album; f["albumArtist"] = albumArtist; f["year"] = year; f["genre"] = genre
        f["trackNumber"] = trackNumber.map(String.init); f["discNumber"] = discNumber.map(String.init)
        return f.filter { !$0.value.isEmpty }
    }
}

/// Letra encontrada (LRCLIB).
public struct LyricsCandidate: Sendable, Identifiable, Equatable {
    public let id: Int
    public let title: String
    public let artist: String
    public let album: String?
    public let duration: Double?
    public let synced: String?
    public let plain: String?
    public let instrumental: Bool

    public init(id: Int, title: String, artist: String, album: String? = nil, duration: Double? = nil,
                synced: String? = nil, plain: String? = nil, instrumental: Bool = false) {
        self.id = id; self.title = title; self.artist = artist; self.album = album
        self.duration = duration; self.synced = synced; self.plain = plain; self.instrumental = instrumental
    }

    public var isSynced: Bool { !(synced ?? "").isEmpty }
    /// Texto a salvar no .lrc (sincronizada quando houver).
    public var text: String? { isSynced ? synced : (plain?.isEmpty == false ? plain : nil) }
}
