import Foundation

/// Imagem de capa a embutir (substitui todas as imagens do arquivo por uma capa frontal).
public struct CoverImage: Sendable, Equatable, Codable {
    public let data: Data
    public let mimeType: String
    /// Impressão dos bytes, calculada uma vez: comparar capas não percorre a imagem inteira.
    private let fingerprint: Int

    public init(data: Data, mimeType: String = "image/jpeg") {
        self.data = data
        self.mimeType = mimeType
        self.fingerprint = data.hashValue
    }

    enum CodingKeys: String, CodingKey { case data, mimeType }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(data: try c.decode(Data.self, forKey: .data), mimeType: try c.decode(String.self, forKey: .mimeType))
    }

    public static func == (a: CoverImage, b: CoverImage) -> Bool {
        a.fingerprint == b.fingerprint && a.data.count == b.data.count && a.mimeType == b.mimeType
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
