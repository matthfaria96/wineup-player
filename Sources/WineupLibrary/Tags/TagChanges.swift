import Foundation

/// Imagem de capa a embutir (substitui todas as imagens do arquivo por uma capa frontal).
public struct CoverImage: Sendable, Equatable, Codable {
    public var data: Data
    public var mimeType: String

    public init(data: Data, mimeType: String = "image/jpeg") {
        self.data = data
        self.mimeType = mimeType
    }
}

/// Alterações de tag pedidas; campo nil significa "não mexer".
public struct TagChanges: Sendable, Equatable, Codable {
    public var title: String?
    public var artist: String?
    public var album: String?
    public var albumArtist: String?
    public var genre: String?
    public var year: String?
    public var trackNumber: Int?
    public var discNumber: Int?
    public var composer: String?
    public var comment: String?
    public var cover: CoverImage?

    public init(title: String? = nil, artist: String? = nil, album: String? = nil,
                albumArtist: String? = nil, genre: String? = nil, year: String? = nil,
                trackNumber: Int? = nil, discNumber: Int? = nil,
                composer: String? = nil, comment: String? = nil, cover: CoverImage? = nil) {
        self.title = title; self.artist = artist; self.album = album
        self.albumArtist = albumArtist; self.genre = genre; self.year = year
        self.trackNumber = trackNumber; self.discNumber = discNumber
        self.composer = composer; self.comment = comment; self.cover = cover
    }

    public var isEmpty: Bool { self == TagChanges() }
}
