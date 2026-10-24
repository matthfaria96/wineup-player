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

/// Implementada por SFBAudioEngineAdapter em WineupAudio.
public protocol AudioEngine: AnyObject {
    func play(_ url: URL) throws
    func enqueue(_ url: URL) throws
    func pause()
    func resume()
    func stop()
    func seek(toFraction fraction: Double)
    func setVolume(_ volume: Double)
    func setRate(_ rate: Double)
    func setBalance(_ pan: Double)
    func applyEqualizer(preamp: Double, bands: [Double], bypass: Bool)
    var currentTime: TimeInterval { get }
    var totalTime: TimeInterval { get }
    var isPlaying: Bool { get }
}
