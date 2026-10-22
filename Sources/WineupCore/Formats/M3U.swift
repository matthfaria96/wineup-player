import Foundation

/// Playlists M3U/M3U8: leitura (relativo, absoluto, file://, #EXTINF) e escrita em UTF-8.
public enum M3U {
    public struct Entry: Equatable, Sendable {
        public let url: URL
        public let title: String?
        public let duration: Int?
    }

    public static func parse(_ text: String, baseDirectory: URL) -> [Entry] {
        var entries: [Entry] = []
        var pendingTitle: String?
        var pendingDuration: Int?
        for raw in text.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }
            if line.hasPrefix("#EXTINF:") {
                let info = line.dropFirst(8)
                let comma = info.firstIndex(of: ",")
                pendingDuration = Int(info[..<(comma ?? info.endIndex)].trimmingCharacters(in: .whitespaces))
                pendingTitle = comma.map { String(info[info.index(after: $0)...]).trimmingCharacters(in: .whitespaces) }
                continue
            }
            if line.hasPrefix("#") { continue }
            let url: URL
            if line.lowercased().hasPrefix("file://"), let parsed = URL(string: line) {
                url = parsed
            } else if line.hasPrefix("/") {
                url = URL(fileURLWithPath: line)
            } else if line.contains("://") {
                continue   // streams/URLs remotas não são suportadas
            } else {
                url = baseDirectory.appendingPathComponent(line.replacingOccurrences(of: "\\", with: "/"))
            }
            entries.append(Entry(url: url.standardizedFileURL, title: pendingTitle, duration: pendingDuration))
            pendingTitle = nil
            pendingDuration = nil
        }
        return entries
    }

    /// Lê arquivo .m3u/.m3u8: UTF-8, com recaída para Latin-1 (M3U antigo).
    public static func read(_ file: URL) throws -> [Entry] {
        let data = try Data(contentsOf: file)
        let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) ?? ""
        return parse(text, baseDirectory: file.deletingLastPathComponent())
    }

    public static func write(_ tracks: [Track]) -> String {
        var out = "#EXTM3U\n"
        for track in tracks {
            guard let url = track.url else { continue }
            out += "#EXTINF:\(track.duration),\(track.artist) - \(track.title)\n\(url.path)\n"
        }
        return out
    }
}
