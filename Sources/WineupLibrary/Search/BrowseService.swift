import Foundation
import GRDB

public struct ArtistSummary: Sendable, Equatable, Identifiable {
    public let id: Int64; public let name: String; public let trackCount: Int
}
public struct AlbumSummary: Sendable, Equatable, Identifiable {
    public let id: Int64; public let title: String; public let artist: String
    public let year: String?; public let kind: String; public let trackCount: Int
}
public struct GenreSummary: Sendable, Equatable, Identifiable {
    public let name: String; public let trackCount: Int
    public var id: String { name }
}
public struct FolderSummary: Sendable, Equatable, Identifiable {
    public let path: String; public let trackCount: Int
    public var id: String { path }
}

/// Navegação por artista, álbum, gênero, pasta e todas as faixas. Somente leitura.
public struct BrowseService: Sendable {
    public static let uncategorizedGenre = "Sem categoria"
    public static let singlesID: Int64 = -1
    public static let singlesTitle = "Singles"

    private let database: LibraryDatabase
    public init(database: LibraryDatabase) { self.database = database }

    private func statusClause(_ includeMissing: Bool) -> String {
        includeMissing ? "1=1" : "af.status = 'present'"
    }
    private static let order = "ORDER BY rel.title, rt.disc_number, rt.track_number, rec.title"
    private static let genreExpr = "COALESCE(NULLIF(rt.genre, ''), ?)"

    private func tracks(where clause: String, args: StatementArguments, orderBy: String = order,
                        limit: Int? = nil, offset: Int = 0) async throws -> [LibraryTrack] {
        var sql = LibraryTrack.baseSelect + "\nWHERE \(clause)\n\(orderBy)"
        var arguments = args
        if let limit { sql += " LIMIT ? OFFSET ?"; arguments += [limit, offset] }
        let finalSQL = sql, finalArgs = arguments
        return try await database.pool.read { db in
            try Row.fetchAll(db, sql: finalSQL, arguments: finalArgs).map(LibraryTrack.make)
        }
    }

    public func artists(includeMissing: Bool = false) async throws -> [ArtistSummary] {
        let sql = """
            SELECT ar.id AS id, ar.name AS name, COUNT(*) AS n
            FROM audio_file af JOIN release_track rt ON rt.audio_file_id = af.id
            JOIN recording rec ON rec.id = rt.recording_id
            JOIN artist ar ON ar.id = rec.artist_id
            WHERE \(statusClause(includeMissing)) GROUP BY ar.id ORDER BY ar.sort_key
            """
        return try await database.pool.read { db in
            try Row.fetchAll(db, sql: sql).map { ArtistSummary(id: $0["id"], name: $0["name"], trackCount: $0["n"]) }
        }
    }

    public func tracks(artistID: Int64, includeMissing: Bool = false) async throws -> [LibraryTrack] {
        try await tracks(where: "rec.artist_id = ? AND \(statusClause(includeMissing))", args: [artistID])
    }

    public func albums(includeMissing: Bool = false) async throws -> [AlbumSummary] {
        let sql = """
            SELECT rel.id AS id, rel.title AS title, COALESCE(ar.name, '') AS artist,
                   rel.year AS year, rel.kind AS kind, COUNT(*) AS n
            FROM audio_file af JOIN release_track rt ON rt.audio_file_id = af.id
            JOIN release rel ON rel.id = rt.release_id
            LEFT JOIN artist ar ON ar.id = rel.album_artist_id
            WHERE \(statusClause(includeMissing)) GROUP BY rel.id ORDER BY rel.title COLLATE NOCASE
            """
        return try await database.pool.read { db in
            try Row.fetchAll(db, sql: sql).map {
                AlbumSummary(id: $0["id"], title: $0["title"], artist: $0["artist"],
                             year: $0["year"], kind: $0["kind"], trackCount: $0["n"])
            }
        }
    }

    public func tracks(releaseID: Int64, includeMissing: Bool = false) async throws -> [LibraryTrack] {
        try await tracks(where: "rt.release_id = ? AND \(statusClause(includeMissing))", args: [releaseID],
                         orderBy: "ORDER BY rt.disc_number, rt.track_number, rec.title")
    }

    public func genres(includeMissing: Bool = false) async throws -> [GenreSummary] {
        let sql = """
            SELECT \(Self.genreExpr) AS g, COUNT(*) AS n
            FROM audio_file af JOIN release_track rt ON rt.audio_file_id = af.id
            WHERE \(statusClause(includeMissing)) GROUP BY g ORDER BY g COLLATE NOCASE
            """
        let unc = Self.uncategorizedGenre
        return try await database.pool.read { db in
            try Row.fetchAll(db, sql: sql, arguments: [unc]).map { GenreSummary(name: $0["g"], trackCount: $0["n"]) }
        }
    }

    public func tracks(genre: String, includeMissing: Bool = false) async throws -> [LibraryTrack] {
        try await tracks(where: "\(Self.genreExpr) = ? AND \(statusClause(includeMissing))",
                         args: [Self.uncategorizedGenre, genre])
    }

    /// Pastas: agrupa pelo diretório pai do caminho, em SQL
    /// (`rtrim(path, nao-barras)` deixa o caminho até a última "/"), dentro da raiz informada.
    public func folders(rootID: Int64, includeMissing: Bool = false) async throws -> [FolderSummary] {
        let sql = """
            SELECT substr(af.path, 1, length(rtrim(af.path, replace(af.path, '/', ''))) - 1) AS dir,
                   COUNT(*) AS n
            FROM audio_file af
            WHERE af.root_id = ? AND \(statusClause(includeMissing)) GROUP BY dir ORDER BY dir
            """
        return try await database.pool.read { db in
            try Row.fetchAll(db, sql: sql, arguments: [rootID]).map { FolderSummary(path: $0["dir"], trackCount: $0["n"]) }
        }
    }

    public func tracks(inFolder folder: String, includeMissing: Bool = false) async throws -> [LibraryTrack] {
        let dir = folder.hasSuffix("/") ? String(folder.dropLast()) : folder
        let expr = "substr(af.path, 1, length(rtrim(af.path, replace(af.path, '/', ''))) - 1)"
        return try await tracks(where: "\(expr) = ? AND \(statusClause(includeMissing))", args: [dir],
                                orderBy: "ORDER BY af.path")
    }

    public func allTracks(limit: Int = 200, offset: Int = 0, includeMissing: Bool = false) async throws -> [LibraryTrack] {
        try await tracks(where: statusClause(includeMissing), args: [],
                         orderBy: "ORDER BY af.id", limit: limit, offset: offset)
    }

    // MARK: Singles (álbum virtual, somente consulta)

    private func singlesClause(_ includeMissing: Bool) -> String {
        let st = statusClause(includeMissing)
        return """
            \(st) AND (rel.id IS NULL OR rel.title = 'Unknown Album' OR
              (SELECT COUNT(*) FROM release_track rt2 JOIN audio_file af2 ON af2.id = rt2.audio_file_id
               WHERE rt2.release_id = rt.release_id AND \(includeMissing ? "1=1" : "af2.status = 'present'")) = 1)
            """
    }

    public func singles(includeMissing: Bool = false) async throws -> [LibraryTrack] {
        try await tracks(where: singlesClause(includeMissing), args: [], orderBy: "ORDER BY rec.title COLLATE NOCASE")
    }

    public func singlesSummary(includeMissing: Bool = false) async throws -> AlbumSummary {
        let n = try await singles(includeMissing: includeMissing).count
        return AlbumSummary(id: Self.singlesID, title: Self.singlesTitle, artist: "",
                            year: nil, kind: "single", trackCount: n)
    }
}
