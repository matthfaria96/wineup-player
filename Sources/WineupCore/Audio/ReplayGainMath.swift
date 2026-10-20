import Foundation

public enum ReplayGainMode: String, Sendable, CaseIterable {
    case off, track, album
}

public struct ReplayGainInfo: Sendable, Equatable {
    public var trackGain: Double?
    public var trackPeak: Double?
    public var albumGain: Double?
    public var albumPeak: Double?

    public init(trackGain: Double? = nil, trackPeak: Double? = nil,
                albumGain: Double? = nil, albumPeak: Double? = nil) {
        self.trackGain = trackGain
        self.trackPeak = trackPeak
        self.albumGain = albumGain
        self.albumPeak = albumPeak
    }
}

public enum ReplayGainMath {
    static let maxAbsDB = 30.0

    /// Ganho linear. Tags são não confiáveis: NaN/Inf viram 1,0, dB limitado a +/-30,
    /// pico <= 0 ou não finito é ignorado.
    public static func linearGain(mode: ReplayGainMode, info: ReplayGainInfo, preventClipping: Bool) -> Double {
        guard mode != .off else { return 1 }
        let album = mode == .album
        let rawDB = album ? (info.albumGain ?? info.trackGain) : (info.trackGain ?? info.albumGain)
        guard let db = rawDB, db.isFinite else { return 1 }
        let clamped = min(maxAbsDB, max(-maxAbsDB, db))
        let linear = pow(10, clamped / 20)
        guard preventClipping else { return linear }
        let rawPeak = album ? (info.albumPeak ?? info.trackPeak) : (info.trackPeak ?? info.albumPeak)
        if let peak = rawPeak, peak.isFinite, peak > 0 {
            return min(linear, 1 / peak)
        }
        return linear
    }
}
