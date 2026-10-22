import Foundation

/// Letra sincronizada: cada linha com o instante (s) em que começa.
public struct TimedLyrics: Equatable, Sendable {
    public struct Line: Equatable, Sendable {
        public let time: Double
        public let text: String
    }
    public let lines: [Line]

    /// Índice da linha ativa no instante `time` (nil antes da primeira).
    public func index(at time: Double) -> Int? {
        var low = 0, high = lines.count - 1, found: Int?
        while low <= high {
            let mid = (low + high) / 2
            if lines[mid].time <= time { found = mid; low = mid + 1 } else { high = mid - 1 }
        }
        return found
    }
}

/// Leitor de .lrc: "[mm:ss.xx] texto", várias marcas por linha e "[offset:+/-ms]".
public enum LRCParser {
    public static func parse(_ text: String) -> TimedLyrics? {
        var offset = 0.0
        var lines: [TimedLyrics.Line] = []
        for raw in text.components(separatedBy: .newlines) {
            var rest = Substring(raw.trimmingCharacters(in: .whitespaces))
            var times: [Double] = []
            while rest.hasPrefix("["), let close = rest.firstIndex(of: "]") {
                let tag = rest[rest.index(after: rest.startIndex)..<close]
                if let t = time(of: tag) {
                    times.append(t)
                } else if tag.lowercased().hasPrefix("offset:") {
                    offset = (Double(tag.dropFirst(7).trimmingCharacters(in: .whitespaces)) ?? 0) / 1000
                }
                rest = rest[rest.index(after: close)...]
            }
            let words = rest.trimmingCharacters(in: .whitespaces)
            lines += times.map { TimedLyrics.Line(time: $0, text: words) }
        }
        guard !lines.isEmpty else { return nil }
        let shifted = lines.map { TimedLyrics.Line(time: max(0, $0.time - offset), text: $0.text) }
        return TimedLyrics(lines: shifted.sorted { $0.time < $1.time })
    }

    /// "mm:ss", "mm:ss.xx" ou "mm:ss:xx" em segundos.
    static func time(of tag: Substring) -> Double? {
        let parts = tag.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count >= 2, let minutes = Double(parts[0]), minutes >= 0 else { return nil }
        let secondsText = parts.count == 3 ? "\(parts[1]).\(parts[2])" : String(parts[1])
        guard let seconds = Double(secondsText), seconds >= 0, seconds < 60 else { return nil }
        return minutes * 60 + seconds
    }
}
