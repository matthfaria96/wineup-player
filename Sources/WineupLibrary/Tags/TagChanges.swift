import Foundation

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

    public init(title: String? = nil, artist: String? = nil, album: String? = nil,
                albumArtist: String? = nil, genre: String? = nil, year: String? = nil,
                trackNumber: Int? = nil, discNumber: Int? = nil) {
        self.title = title; self.artist = artist; self.album = album
        self.albumArtist = albumArtist; self.genre = genre; self.year = year
        self.trackNumber = trackNumber; self.discNumber = discNumber
    }

    public var isEmpty: Bool { self == TagChanges() }
}
