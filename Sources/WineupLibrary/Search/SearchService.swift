import Foundation
import GRDB

/// Busca FTS5 sem acento/caixa, com entrada sanitizada (T-02-10).
public struct SearchService: Sendable {
    private let database: LibraryDatabase

    public init(database: LibraryDatabase) { self.database = database }

    public func search(_ text: String, limit: Int = 200) async throws -> [LibraryTrack] {
        guard let q = Self.ftsQuery(text) else { return [] }
        let sql = LibraryTrack.baseSelect + """

            JOIN track_fts ON track_fts.rowid = af.id
            WHERE track_fts MATCH ? AND af.status = 'present' AND af.hidden = 0
            ORDER BY rank LIMIT ?
            """
        return try await database.pool.read { db in
            try Row.fetchAll(db, sql: sql, arguments: [q, limit]).map(LibraryTrack.make)
        }
    }

    /// Cada token vira `"tok"*`; aspas e operadores FTS viram literais.
    static func ftsQuery(_ text: String) -> String? {
        let tokens = text.split(whereSeparator: { !($0.isLetter || $0.isNumber) })
            .map { String($0.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }) }
            .filter { !$0.isEmpty }
        guard !tokens.isEmpty else { return nil }
        return tokens.map { "\"\($0)\"*" }.joined(separator: " ")
    }
}
