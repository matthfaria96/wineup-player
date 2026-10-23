import Foundation

public struct TrackID: Hashable, Sendable, Codable, CustomStringConvertible {
    public let rawValue: UUID
    public init(_ rawValue: UUID = UUID()) { self.rawValue = rawValue }

    /// ID estável derivado de uma chave (ex.: caminho do arquivo): a mesma faixa
    /// tem o mesmo ID em qualquer lista e entre recargas. Hash FNV-1a de 128 bits.
    public init(stableKey key: String) {
        func fnv(_ seed: UInt64) -> UInt64 {
            var h = seed
            for b in key.utf8 { h = (h ^ UInt64(b)) &* 0x100_0000_01B3 }
            return h
        }
        let a = fnv(0xCBF2_9CE4_8422_2325), b = fnv(0x84222325CBF29CE4)
        func byte(_ v: UInt64, _ i: Int) -> UInt8 { UInt8(truncatingIfNeeded: v >> (8 * i)) }
        rawValue = UUID(uuid: (byte(a, 0), byte(a, 1), byte(a, 2), byte(a, 3), byte(a, 4), byte(a, 5), byte(a, 6), byte(a, 7),
                               byte(b, 0), byte(b, 1), byte(b, 2), byte(b, 3), byte(b, 4), byte(b, 5), byte(b, 6), byte(b, 7)))
    }
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
    public var mark: MarkColor?
    public var url: URL?
    public var album: String?
    public var year: String?
    public var genre: String?
    /// Trecho dentro do arquivo (faixas de CUE): início e fim em segundos.
    public var start: Double?
    public var end: Double?
    /// Chave na biblioteca quando difere do arquivo (faixa de CUE: "<arquivo.cue>#<n>").
    public var libraryPath: String?

    public init(id: TrackID = TrackID(), artist: String, title: String, duration: Int,
                mark: MarkColor?, url: URL? = nil, album: String? = nil, year: String? = nil,
                genre: String? = nil, start: Double? = nil, end: Double? = nil, libraryPath: String? = nil) {
        self.id = id
        self.artist = artist
        self.title = title
        self.duration = duration
        self.mark = mark
        self.url = url
        self.album = album
        self.year = year
        self.genre = genre
        self.start = start
        self.end = end
        self.libraryPath = libraryPath
    }

    /// Chave usada para tags de cor, playlists e sessão.
    public var storeKey: String? { libraryPath ?? url?.path }

    /// Faixa que é um trecho de um arquivo maior (CUE).
    public var isSegment: Bool { start != nil }

    public var displayName: String { "\(artist) - \(title)" }
}
