import Foundation

/// Qual cópia manter num grupo de duplicadas: sem perda primeiro, depois maior bitrate,
/// depois a mais completa (capa, letra, tags). Só sugere: remover sempre exige confirmação.
public enum DuplicateRanking {
    static let lossless: Set<String> = ["flac", "wav", "wave", "aif", "aiff", "alac", "ape", "wv"]

    public static func score(_ f: FixerFile) -> Double {
        var s = 0.0
        let ext = f.url.pathExtension.lowercased()
        if lossless.contains(ext) || f.tech.codec.lowercased().contains("lossless") || f.tech.codec.lowercased().contains("alac") {
            s += 10_000
        }
        s += Double(f.tech.bitrate ?? 0)
        if f.hasCover { s += 50 }
        if f.hasLyrics { s += 30 }
        s += Double(["title", "artist", "album", "year", "trackNumber", "genre", "albumArtist"]
            .filter { !f.value($0).isEmpty }.count) * 5
        return s
    }

    /// Grupos (número → arquivos), cada um com o recomendado primeiro.
    public static func groups(_ files: [FixerFile]) -> [(group: Int, files: [FixerFile])] {
        Dictionary(grouping: files.filter { $0.duplicateGroup != nil }) { $0.duplicateGroup! }
            .map { ($0.key, $0.value.sorted { score($0) > score($1) }) }
            .sorted { $0.group < $1.group }
    }

    /// Explica por que a cópia recomendada é a melhor.
    public static func reason(best: FixerFile, other: FixerFile) -> String {
        let bExt = best.url.pathExtension.lowercased(), oExt = other.url.pathExtension.lowercased()
        if lossless.contains(bExt) && !lossless.contains(oExt) { return "sem perda (\(bExt.uppercased()))" }
        if (best.tech.bitrate ?? 0) > (other.tech.bitrate ?? 0) { return "maior qualidade (\(best.tech.bitrateText))" }
        if best.hasCover && !other.hasCover { return "tem capa" }
        if best.hasLyrics && !other.hasLyrics { return "tem letra" }
        return "tags mais completas"
    }
}

/// Problemas que o usuário mandou ignorar (por arquivo); não voltam nas próximas análises.
public final class IgnoredIssuesStore: @unchecked Sendable {
    public static let shared = IgnoredIssuesStore()
    private let url: URL
    private let lock = NSLock()

    public init(directory: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Wineup", isDirectory: true)) {
        url = directory.appendingPathComponent("ignored-issues.json")
    }

    public func all() -> [String: Set<FixerIssue>] {
        lock.withLock { load() }
    }

    public func set(_ issues: Set<FixerIssue>, for path: String) throws {
        try lock.withLock {
            var map = load()
            map[path] = issues.isEmpty ? nil : issues
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let raw = map.mapValues { $0.map(\.rawValue).sorted() }
            try JSONEncoder().encode(raw).write(to: url, options: .atomic)
        }
    }

    private func load() -> [String: Set<FixerIssue>] {
        guard let data = try? Data(contentsOf: url),
              let raw = try? JSONDecoder().decode([String: [String]].self, from: data) else { return [:] }
        return raw.mapValues { Set($0.compactMap(FixerIssue.init(rawValue:))) }
    }
}
