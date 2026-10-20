import Foundation

public struct TrackID: Hashable, Sendable, Codable, CustomStringConvertible {
    public let rawValue: UUID
    public init(_ rawValue: UUID = UUID()) { self.rawValue = rawValue }
    public var description: String { rawValue.uuidString }

    /// Semente determinística (não usa hashValue, que varia por execução).
    public var seed: Int {
        let u = rawValue.uuid
        return Int(u.0) << 8 | Int(u.1)
    }
}

public enum MarkColor: String, CaseIterable, Identifiable, Sendable, Codable {
    case green, blue, purple, red, orange, yellow
    public var id: String { rawValue }
}

public struct Track: Identifiable, Hashable, Sendable {
    public let id: TrackID
    public let artist: String
    public let title: String
    public let duration: Int
    public let mark: MarkColor?
    public var url: URL?
    public var album: String?
    public var year: String?

    public init(id: TrackID = TrackID(), artist: String, title: String, duration: Int,
                mark: MarkColor?, url: URL? = nil, album: String? = nil, year: String? = nil) {
        self.id = id
        self.artist = artist
        self.title = title
        self.duration = duration
        self.mark = mark
        self.url = url
        self.album = album
        self.year = year
    }

    public var displayName: String { "\(artist) - \(title)" }
}
