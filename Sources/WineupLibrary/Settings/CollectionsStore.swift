import Foundation
import GRDB

/// Playlist do usuário com os caminhos dos arquivos, na ordem.
public struct UserPlaylist: Sendable, Equatable, Identifiable {
    public let id: Int64
    public let uuid: String
    public let name: String
    public let paths: [String]
}

/// O que o usuário montou sobre a biblioteca: marcações de cor por faixa e playlists.
/// Nunca grava nos arquivos de áudio; tudo fica no banco do app.
public struct CollectionsStore: Sendable {
    private let database: LibraryDatabase
    public init(database: LibraryDatabase) { self.database = database }

    // MARK: Marcações de cor

    /// Caminho → cor (`MarkColor.rawValue`).
    public func marks() throws -> [String: String] {
        try database.pool.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT af.path AS path, tm.color AS color
                FROM track_mark tm JOIN audio_file af ON af.id = tm.audio_file_id
                """)
            return Dictionary(rows.map { ($0["path"] as String, $0["color"] as String) },
                              uniquingKeysWith: { _, last in last })
        }
    }

    /// Define (ou remove, com `nil`) a cor de uma faixa. Retorna `false` se o arquivo não está na biblioteca.
    @discardableResult
    public func setMark(path: String, color: String?) throws -> Bool {
        try database.pool.write { db in
            guard let fileID = try Int64.fetchOne(db, sql: "SELECT id FROM audio_file WHERE path = ?",
                                                  arguments: [path]) else { return false }
            try db.execute(sql: "DELETE FROM track_mark WHERE audio_file_id = ?", arguments: [fileID])
            if let color {
                try db.execute(sql: "INSERT INTO track_mark (audio_file_id, color, updated_at) VALUES (?, ?, ?)",
                               arguments: [fileID, color, Date()])
            }
            return true
        }
    }

    /// Cores com pelo menos uma faixa presente, e quantas faixas cada uma tem.
    public func markCounts() throws -> [String: Int] {
        try database.pool.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT tm.color AS color, COUNT(*) AS n
                FROM track_mark tm JOIN audio_file af ON af.id = tm.audio_file_id
                WHERE af.status = 'present' AND af.hidden = 0 GROUP BY tm.color
                """)
            return Dictionary(uniqueKeysWithValues: rows.map { ($0["color"] as String, $0["n"] as Int) })
        }
    }

    public func tracks(markedWith color: String) throws -> [LibraryTrack] {
        try database.pool.read { db in
            try Row.fetchAll(db, sql: LibraryTrack.baseSelect + """

                JOIN track_mark tm ON tm.audio_file_id = af.id
                WHERE tm.color = ? AND af.status = 'present' AND af.hidden = 0
                ORDER BY rec.title COLLATE NOCASE
                """, arguments: [color]).map(LibraryTrack.make)
        }
    }

    // MARK: Playlists

    public func playlists() throws -> [UserPlaylist] {
        try database.pool.read { db in
            let lists = try Row.fetchAll(db, sql: "SELECT id, uuid, name FROM playlist ORDER BY name COLLATE NOCASE")
            return try lists.map { row in
                let id: Int64 = row["id"]
                let paths = try String.fetchAll(db, sql: """
                    SELECT af.path FROM playlist_item pi JOIN audio_file af ON af.id = pi.audio_file_id
                    WHERE pi.playlist_id = ? ORDER BY pi.position
                    """, arguments: [id])
                return UserPlaylist(id: id, uuid: row["uuid"], name: row["name"], paths: paths)
            }
        }
    }

    /// Cria uma playlist; se o nome já existir, acrescenta " (2)", " (3)"...
    @discardableResult
    public func createPlaylist(named name: String) throws -> UserPlaylist {
        try database.pool.write { db in
            let base = name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Nova playlist" : name
            let existing = Set(try String.fetchAll(db, sql: "SELECT name FROM playlist").map { $0.lowercased() })
            var finalName = base
            var n = 2
            while existing.contains(finalName.lowercased()) { finalName = "\(base) (\(n))"; n += 1 }
            let uuid = UUID().uuidString
            try db.execute(sql: "INSERT INTO playlist (uuid, name, created_at, updated_at) VALUES (?, ?, ?, ?)",
                           arguments: [uuid, finalName, Date(), Date()])
            return UserPlaylist(id: db.lastInsertedRowID, uuid: uuid, name: finalName, paths: [])
        }
    }

    public func renamePlaylist(id: Int64, to name: String) throws {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        try database.pool.write { db in
            try db.execute(sql: "UPDATE playlist SET name = ?, updated_at = ? WHERE id = ?",
                           arguments: [trimmed, Date(), id])
        }
    }

    public func deletePlaylist(id: Int64) throws {
        try database.pool.write { db in
            try db.execute(sql: "DELETE FROM playlist_item WHERE playlist_id = ?", arguments: [id])
            try db.execute(sql: "DELETE FROM playlist WHERE id = ?", arguments: [id])
        }
    }

    /// Acrescenta faixas ao fim da playlist (ignora caminhos fora da biblioteca). Retorna quantas entraram.
    @discardableResult
    public func append(paths: [String], toPlaylist id: Int64) throws -> Int {
        try database.pool.write { db in
            var position = (try Int.fetchOne(db, sql: "SELECT MAX(position) FROM playlist_item WHERE playlist_id = ?",
                                             arguments: [id]) ?? -1) + 1
            var added = 0
            for path in paths {
                guard let fileID = try Int64.fetchOne(db, sql: "SELECT id FROM audio_file WHERE path = ?",
                                                      arguments: [path]) else { continue }
                try db.execute(sql: "INSERT INTO playlist_item (playlist_id, audio_file_id, position) VALUES (?, ?, ?)",
                               arguments: [id, fileID, position])
                position += 1
                added += 1
            }
            try db.execute(sql: "UPDATE playlist SET updated_at = ? WHERE id = ?", arguments: [Date(), id])
            return added
        }
    }

    /// Remove a primeira ocorrência do arquivo na playlist e recompacta as posições.
    public func remove(path: String, fromPlaylist id: Int64) throws {
        try database.pool.write { db in
            guard let itemID = try Int64.fetchOne(db, sql: """
                SELECT pi.id FROM playlist_item pi JOIN audio_file af ON af.id = pi.audio_file_id
                WHERE pi.playlist_id = ? AND af.path = ? ORDER BY pi.position LIMIT 1
                """, arguments: [id, path]) else { return }
            try db.execute(sql: "DELETE FROM playlist_item WHERE id = ?", arguments: [itemID])
            let ids = try Int64.fetchAll(db, sql: "SELECT id FROM playlist_item WHERE playlist_id = ? ORDER BY position",
                                         arguments: [id])
            // Duas passadas para não violar UNIQUE(playlist_id, position) durante a renumeração.
            for (n, item) in ids.enumerated() {
                try db.execute(sql: "UPDATE playlist_item SET position = ? WHERE id = ?", arguments: [-(n + 1), item])
            }
            try db.execute(sql: "UPDATE playlist_item SET position = -position - 1 WHERE playlist_id = ?", arguments: [id])
        }
    }

    public func tracks(inPlaylist id: Int64) throws -> [LibraryTrack] {
        try database.pool.read { db in
            try Row.fetchAll(db, sql: LibraryTrack.baseSelect + """

                JOIN playlist_item pi ON pi.audio_file_id = af.id
                WHERE pi.playlist_id = ?
                ORDER BY pi.position
                """, arguments: [id]).map(LibraryTrack.make)
        }
    }

    // MARK: Faixas de uma pasta (recursivo)

    /// Faixas presentes cujo caminho está dentro de `folder` (inclui subpastas).
    /// Faixa de caminhos [prefixo/, prefixo0): usa o índice de `path` (LIKE não usa).
    public func tracks(under folder: String) throws -> [LibraryTrack] {
        let prefix = folder.hasSuffix("/") ? folder : folder + "/"
        // "0" vem logo depois de "/" na ordem binária: tudo que começa com o prefixo fica antes dele.
        let upper = String(prefix.dropLast()) + "0"
        return try database.pool.read { db in
            try Row.fetchAll(db, sql: LibraryTrack.baseSelect + """

                WHERE af.status = 'present' AND af.hidden = 0 AND af.path >= ? AND af.path < ?
                ORDER BY ar.name COLLATE NOCASE, rel.title COLLATE NOCASE, rt.disc_number, rt.track_number, rec.title
                """, arguments: [prefix, upper]).map(LibraryTrack.make)
        }
    }

    /// Uma faixa pelo caminho exato (nil se não está na biblioteca).
    public func track(atPath path: String) throws -> LibraryTrack? {
        try database.pool.read { db in
            try Row.fetchOne(db, sql: LibraryTrack.baseSelect + "\nWHERE af.path = ?", arguments: [path])
                .map(LibraryTrack.make)
        }
    }

    /// Várias faixas pelo caminho exato, numa leitura só (consultas IN em lotes). Caminho → faixa.
    public func tracks(atPaths paths: [String]) throws -> [String: LibraryTrack] {
        let unique = Array(Set(paths))
        guard !unique.isEmpty else { return [:] }
        return try database.pool.read { db in
            var found: [String: LibraryTrack] = [:]
            for start in stride(from: 0, to: unique.count, by: 500) {
                let chunk = Array(unique[start..<min(start + 500, unique.count)])
                let marks = Array(repeating: "?", count: chunk.count).joined(separator: ",")
                let rows = try Row.fetchAll(db, sql: LibraryTrack.baseSelect + "\nWHERE af.path IN (\(marks))",
                                            arguments: StatementArguments(chunk))
                for row in rows {
                    let track = LibraryTrack.make(row)
                    if found[track.path] == nil { found[track.path] = track }
                }
            }
            return found
        }
    }

    /// Raízes da biblioteca (caminhos), para saber se uma pasta já está indexada.
    public func rootPaths() throws -> [String] {
        try database.pool.read { db in try String.fetchAll(db, sql: "SELECT path FROM library_root") }
    }

    // MARK: Pastas e busca por caminho/identidade

    /// Pastas com faixas presentes, em todas as raízes.
    public func folders() throws -> [FolderSummary] {
        try database.pool.read { db in
            try Row.fetchAll(db, sql: """
                SELECT substr(path, 1, length(rtrim(path, replace(path, '/', ''))) - 1) AS dir, COUNT(*) AS n
                FROM audio_file WHERE status = 'present' AND hidden = 0 GROUP BY dir ORDER BY dir COLLATE NOCASE
                """).map { FolderSummary(path: $0["dir"], trackCount: $0["n"]) }
        }
    }

    /// Encontra o caminho de uma faixa pelo caminho exato ou, em outra máquina, por título + artista.
    public func resolvePath(path: String, title: String, artist: String) throws -> String? {
        try database.pool.read { db in
            if let exact = try String.fetchOne(db, sql: "SELECT path FROM audio_file WHERE path = ?", arguments: [path]) {
                return exact
            }
            return try String.fetchOne(db, sql: """
                SELECT af.path FROM audio_file af
                JOIN release_track rt ON rt.audio_file_id = af.id
                JOIN recording rec ON rec.id = rt.recording_id
                LEFT JOIN artist ar ON ar.id = rec.artist_id
                WHERE af.status = 'present' AND af.hidden = 0 AND rec.title = ? COLLATE NOCASE
                  AND COALESCE(ar.name, '') = ? COLLATE NOCASE
                LIMIT 1
                """, arguments: [title, artist])
        }
    }
}
