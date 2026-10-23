import Foundation
import WineupCore

/// Que tipo de letra é: sincronizada (cada linha com instante) ou estática (só o texto).
public struct LyricsInfo: Sendable, Equatable {
    public enum Kind: Sendable, Equatable { case synced, plain, empty }

    public struct Line: Sendable, Equatable, Identifiable {
        public var id: Int
        public var time: Double?
        public var text: String
    }

    public let kind: Kind
    public let lines: [Line]
    /// Tags de cabeçalho do .lrc ([ar:], [ti:], [al:], [by:], [length:]...).
    public let header: [String: String]

    public init(_ text: String) {
        let raw = text.components(separatedBy: .newlines)
        var header: [String: String] = [:]
        for line in raw {
            let t = line.trimmingCharacters(in: .whitespaces)
            guard t.hasPrefix("["), t.hasSuffix("]"), let colon = t.firstIndex(of: ":") else { continue }
            let key = t[t.index(after: t.startIndex)..<colon].lowercased()
            guard key.allSatisfy(\.isLetter) else { continue }
            header[key] = String(t[t.index(after: colon)..<t.index(before: t.endIndex)]).trimmingCharacters(in: .whitespaces)
        }
        self.header = header
        if let timed = LRCParser.parse(text), !timed.lines.isEmpty {
            kind = .synced
            lines = timed.lines.enumerated().map { Line(id: $0, time: $1.time, text: $1.text) }
            return
        }
        let plain = raw.map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !($0.hasPrefix("[") && $0.hasSuffix("]") && $0.contains(":")) }
        let trimmed = Array(plain.drop { $0.isEmpty }.reversed().drop { $0.isEmpty }.reversed())
        kind = trimmed.isEmpty ? .empty : .plain
        lines = trimmed.enumerated().map { Line(id: $0, time: nil, text: $1) }
    }

    public var isSynced: Bool { kind == .synced }
    public var firstTime: Double? { lines.first?.time }
    public var lastTime: Double? { lines.last?.time }

    /// Linha ativa no instante `time` (nil antes da primeira ou se a letra é estática).
    public func activeIndex(at time: Double) -> Int? {
        guard isSynced else { return nil }
        return lines.lastIndex { ($0.time ?? .infinity) <= time }
    }

    public var label: String {
        switch kind {
        case .synced: "Sincronizada"
        case .plain: "Estática"
        case .empty: "Vazia"
        }
    }

    /// Explicação curta para quem não conhece .lrc.
    public var summary: String {
        switch kind {
        case .synced:
            let span = [firstTime, lastTime].compactMap { $0 }.map(Self.clock).joined(separator: " a ")
            return "\(lines.count) linhas com marca de tempo (\(span)): acompanha a música, linha por linha."
        case .plain:
            return "\(lines.count) linhas sem marca de tempo: aparece inteira, não acompanha a música."
        case .empty:
            return "Arquivo sem texto."
        }
    }

    public static func clock(_ t: Double) -> String {
        String(format: "%d:%02d.%02d", Int(t) / 60, Int(t) % 60, Int((t - floor(t)) * 100))
    }
}
