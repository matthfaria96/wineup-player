import Foundation

public enum Confidence: Int, Sendable, Comparable, CaseIterable {
    case low, medium, high

    public static func < (lhs: Confidence, rhs: Confidence) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

public struct TagDiff: Sendable, Equatable {
    public let field: String
    public let oldValue: String?
    public let newValue: String?
    public let confidence: Confidence

    public init(field: String, oldValue: String?, newValue: String?, confidence: Confidence) {
        self.field = field
        self.oldValue = oldValue
        self.newValue = newValue
        self.confidence = confidence
    }
}

public struct JournalEntry: Sendable, Equatable, Identifiable {
    public let id: UUID
    public let fileURL: URL
    public let diffs: [TagDiff]
    public let createdAt: Date
    public let backupURL: URL?

    public init(id: UUID = UUID(), fileURL: URL, diffs: [TagDiff], createdAt: Date = Date(), backupURL: URL? = nil) {
        self.id = id
        self.fileURL = fileURL
        self.diffs = diffs
        self.createdAt = createdAt
        self.backupURL = backupURL
    }
}

/// Assinaturas alinhadas a `AudioEngineService` (Sources/Wineup/Audio).
public protocol AudioEngine: AnyObject {
    func play(_ url: URL) throws
    func pause()
    func resume()
    func stop()
    func seek(toFraction fraction: Double)
    func setVolume(_ volume: Double)
}

public protocol TagIO: Sendable {
    func readTags(at url: URL) throws -> [String: String]
    func writeTags(_ tags: [String: String], at url: URL) throws
}

public protocol LibraryStore: Sendable {
    func allTrackURLs() throws -> [URL]
}

public protocol MetadataProvider: Sendable {
    func lookup(artist: String, title: String) async throws -> [TagDiff]
}
