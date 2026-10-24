import Foundation

/// Folha CUE: um arquivo de áudio dividido em faixas (início de cada TRACK pelo INDEX 01).
public struct CueSheet: Equatable, Sendable {
    public struct Entry: Equatable, Sendable {
        public let number: Int
        public let title: String
        public let performer: String
        public let start: Double
        public let end: Double?      // nil = até o fim do arquivo
        public let file: URL
    }

    public let album: String?
    public let entries: [Entry]

    public static func parse(_ text: String, baseDirectory: URL) -> CueSheet? {
        var album: String?, albumPerformer = String(localized: "Desconhecido")
        var file: URL?
        var raw: [(number: Int, title: String?, performer: String?, start: Double?, file: URL)] = []
        for line in text.components(separatedBy: .newlines).map({ $0.trimmingCharacters(in: .whitespaces) }) {
            let upper = line.uppercased()
            if upper.hasPrefix("FILE "), let name = quoted(line) {
                file = baseDirectory.appendingPathComponent(name).standardizedFileURL
            } else if upper.hasPrefix("TRACK "), let file {
                let number = Int(line.split(separator: " ").dropFirst().first ?? "") ?? raw.count + 1
                raw.append((number, nil, nil, nil, file))
            } else if upper.hasPrefix("TITLE "), let value = quoted(line) {
                if raw.isEmpty { album = value } else { raw[raw.count - 1].title = value }
            } else if upper.hasPrefix("PERFORMER "), let value = quoted(line) {
                if raw.isEmpty { albumPerformer = value } else { raw[raw.count - 1].performer = value }
            } else if upper.hasPrefix("INDEX 01 "), !raw.isEmpty {
                raw[raw.count - 1].start = cueTime(String(line.dropFirst(9)))
            }
        }
        let valid = raw.filter { $0.start != nil }
        guard !valid.isEmpty else { return nil }
        let entries = valid.enumerated().map { i, t -> Entry in
            let next = i + 1 < valid.count && valid[i + 1].file == t.file ? valid[i + 1].start : nil
            return Entry(number: t.number, title: t.title ?? String(localized: "Faixa \(t.number)"),
                         performer: t.performer ?? albumPerformer, start: t.start ?? 0, end: next, file: t.file)
        }
        return CueSheet(album: album, entries: entries)
    }

    /// "mm:ss:ff" (75 quadros por segundo) em segundos.
    static func cueTime(_ text: String) -> Double? {
        let parts = text.trimmingCharacters(in: .whitespaces).split(separator: ":").compactMap { Double($0) }
        guard parts.count == 3 else { return nil }
        return parts[0] * 60 + parts[1] + parts[2] / 75
    }

    private static func quoted(_ line: String) -> String? {
        if let first = line.firstIndex(of: "\""), let last = line.lastIndex(of: "\""), first < last {
            return String(line[line.index(after: first)..<last])
        }
        let parts = line.split(separator: " ", maxSplits: 1)
        return parts.count == 2 ? String(parts[1]) : nil
    }
}
