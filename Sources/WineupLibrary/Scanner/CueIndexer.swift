import Foundation
import GRDB
import WineupCore

/// Indexa folhas CUE de uma raiz: cada faixa vira um registro virtual (`<cue>#<n>`) que aponta
/// para o arquivo real (media_path) e o trecho. O arquivo dividido fica escondido nas listas.
/// Idempotente: CUE inalterado não é relido; CUE apagado faz as faixas ficarem ausentes.
enum CueIndexer {
    /// Devolve se algo mudou no banco (faixas novas, alteradas ou ausentes).
    @discardableResult
    static func index(root: URL, rootID: Int64, pool: DatabasePool, now: Date) async throws -> Bool {
        let cues = findCues(under: root)
        let existing: [String: (id: Int64, mtime: Int64, status: String)] = try await pool.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT id, path, mtime_ns, status FROM audio_file WHERE root_id = ? AND media_path IS NOT NULL
                """, arguments: [rootID])
            return Dictionary(rows.map { ($0["path"] as String, ($0["id"] as Int64, $0["mtime_ns"] as Int64, $0["status"] as String)) },
                              uniquingKeysWith: { a, _ in a })
        }
        var seen = Set<String>()
        var covered = Set<String>()
        var changed = false
        for cue in cues {
            guard let sheet = parse(cue.url) else { continue }
            var mediaTags: [String: ScannedTags] = [:]
            for entry in sheet.entries where FileManager.default.fileExists(atPath: entry.file.path) {
                let virtualPath = cue.url.path + "#\(entry.number)"
                seen.insert(virtualPath)
                covered.insert(entry.file.path)
                if let old = existing[virtualPath], old.mtime == cue.mtime, old.status == FileStatus.present.rawValue {
                    continue   // CUE inalterado
                }
                changed = true
                let media = mediaTags[entry.file.path] ?? (try? TagReader.read(entry.file)) ?? ScannedTags()
                mediaTags[entry.file.path] = media
                let mediaDuration = media.duration ?? 0
                let tags = ScannedTags(title: entry.title, artist: entry.performer, albumArtist: media.albumArtist ?? entry.performer,
                                       album: sheet.album ?? media.album, genre: media.genre, year: media.year,
                                       trackNumber: entry.number, discNumber: 1,
                                       duration: max((entry.end ?? mediaDuration) - entry.start, 0))
                try await pool.write { db in
                    let id: Int64
                    if let old = existing[virtualPath] {
                        id = old.id
                        try db.execute(sql: """
                            UPDATE audio_file SET media_path = ?, segment_start = ?, segment_end = ?, mtime_ns = ?,
                                   status = 'present', missing_since = NULL, last_seen_at = ?, duration = ? WHERE id = ?
                            """, arguments: [entry.file.path, entry.start, entry.end, cue.mtime, now, tags.duration, id])
                    } else {
                        try db.execute(sql: """
                            INSERT INTO audio_file(root_id, path, size, mtime_ns, status, last_seen_at, format, duration,
                                                   media_path, segment_start, segment_end)
                            VALUES (?, ?, 0, ?, 'present', ?, 'cue', ?, ?, ?, ?)
                            """, arguments: [rootID, virtualPath, cue.mtime, now, tags.duration, entry.file.path, entry.start, entry.end])
                        id = db.lastInsertedRowID
                    }
                    try CatalogWriter.ingest(db, audioFileID: id, tags: tags, fallbackTitle: entry.title)
                }
            }
        }
        let gone = existing.filter { !seen.contains($0.key) && $0.value.status == FileStatus.present.rawValue }.map(\.value.id)
        try await pool.write { db in
            for id in gone {
                try db.execute(sql: "UPDATE audio_file SET status = 'missing', missing_since = ? WHERE id = ?", arguments: [now, id])
                try CatalogWriter.removeFromIndex(db, audioFileID: id)
            }
            // Esconde os arquivos divididos por um CUE (e mostra de novo os que deixaram de ser).
            try db.execute(sql: "UPDATE audio_file SET hidden = 0 WHERE root_id = ? AND media_path IS NULL AND hidden = 1",
                           arguments: [rootID])
            for path in covered {
                try db.execute(sql: "UPDATE audio_file SET hidden = 1 WHERE path = ? AND media_path IS NULL", arguments: [path])
            }
        }
        return changed || !gone.isEmpty
    }

    private static func findCues(under root: URL) -> [(url: URL, mtime: Int64)] {
        guard let walker = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.contentModificationDateKey],
                                                          options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { return [] }
        var found: [(URL, Int64)] = []
        for case let url as URL in walker where url.pathExtension.lowercased() == "cue" {
            let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            found.append((url.standardizedFileURL, Int64(date.timeIntervalSince1970 * 1_000_000_000)))
        }
        return found
    }

    private static func parse(_ url: URL) -> CueSheet? {
        guard let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else { return nil }
        return CueSheet.parse(text, baseDirectory: url.deletingLastPathComponent())
    }
}
