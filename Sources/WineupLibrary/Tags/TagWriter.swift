import Foundation
import CryptoKit
import GRDB
import WineupCore

/// Erros de gravação. Mensagens não incluem caminhos.
public enum TagWriterError: Error, Equatable {
    case emptyChanges
    case unsupportedFormat
    case insufficientSpace
    case verificationFailed(fields: [String])
    case fileChangedSinceWrite
    case entryNotUndoable
    case writeFailed
}

/// Único ponto de escrita de tags (SAFE-01) e de desfazer (SAFE-02).
public final class TagWriter: Sendable {
    private let database: LibraryDatabase
    private let backups: BackupStore
    private let backendFor: @Sendable (URL) -> TagBackend?

    public init(database: LibraryDatabase, backups: BackupStore,
                backendFor: @escaping @Sendable (URL) -> TagBackend? = { TagBackends.backend(for: $0) }) {
        self.database = database
        self.backups = backups
        self.backendFor = backendFor
    }

    private struct DiffDTO: Codable {
        var field: String
        var old: String?
        var new: String?
    }

    // MARK: Mudanças esperadas

    /// Campos (na nomenclatura do TagSnapshot) com valor novo; "" significa limpar.
    private static func requested(_ c: TagChanges) -> [(String, String)] {
        var out: [(String, String)] = []
        if let v = c.title { out.append(("title", v)) }
        if let v = c.artist { out.append(("artist", v)) }
        if let v = c.album { out.append(("album", v)) }
        if let v = c.albumArtist { out.append(("albumArtist", v)) }
        if let v = c.genre { out.append(("genre", v)) }
        if let v = c.year { out.append(("year", v)) }
        if let v = c.trackNumber { out.append(("trackNumber", String(v))) }
        if let v = c.discNumber { out.append(("discNumber", String(v))) }
        if let v = c.composer { out.append(("composer", v)) }
        if let v = c.comment { out.append(("comment", v)) }
        return out
    }

    /// Imagens esperadas depois de gravar a capa (todas trocadas por uma capa frontal).
    /// MP4 (covr) não guarda o tipo da imagem: volta como "outra" (0).
    private static func expectedPictures(_ c: TagChanges, before: TagSnapshot, url: URL) -> [TagSnapshot.PictureInfo] {
        guard let cover = c.cover, !cover.data.isEmpty else { return before.pictures }
        let digest = SHA256.hash(data: cover.data).map { String(format: "%02x", $0) }.joined()
        let typeless = ["m4a", "mp4", "aac", "alac"].contains(url.pathExtension.lowercased())
        return [TagSnapshot.PictureInfo(type: typeless ? 0 : 3, byteCount: cover.data.count, sha256: digest)]
    }

    private static func describe(_ pictures: [TagSnapshot.PictureInfo]) -> String? {
        guard let first = pictures.first else { return nil }
        let kb = max(1, first.byteCount / 1024)
        return pictures.count == 1 ? String(localized: "capa (\(kb) KB)") : String(localized: "\(pictures.count) imagens")
    }

    /// Só campos cujo valor realmente muda; valor vazio equivale a ausente.
    private static func effective(_ c: TagChanges, before: TagSnapshot, url: URL) -> [(field: String, old: String?, new: String?)] {
        var out: [(field: String, old: String?, new: String?)] = requested(c).compactMap { field, value in
            let new: String? = value.isEmpty ? nil : value
            let old = before.fields[field]
            return old == new ? nil : (field, old, new)
        }
        let pictures = expectedPictures(c, before: before, url: url)
        if pictures != before.pictures {
            out.append(("pictures", describe(before.pictures), describe(pictures)))
        }
        return out
    }

    private func load(_ fileID: Int64) throws -> (record: AudioFileRecord, url: URL) {
        let record = try database.pool.read { try AudioFileRecord.fetchOne($0, key: fileID) }
        guard let record else { throw LibraryError.outsideRoots }
        let url = URL(fileURLWithPath: record.path)
        let roots = try LibraryRootStore(db: database).roots()
        guard roots.contains(where: { $0.contains(url) }) else { throw LibraryError.outsideRoots }
        return (record, url)
    }

    /// Arquivo escolhido pelo usuário no gerenciador de metadados (pode estar fora da biblioteca).
    /// Mesma cópia de trabalho, verificação, backup e diário; o banco só é atualizado se o arquivo for indexado.
    @discardableResult
    public func apply(_ changes: TagChanges, url: URL) throws -> JournalEntry {
        let path = url.standardizedFileURL.path
        let fileID = try database.pool.read {
            try Int64.fetchOne($0, sql: "SELECT id FROM audio_file WHERE path = ?", arguments: [path])
        }
        if let fileID { return try apply(changes, fileID: fileID) }
        guard FileManager.default.fileExists(atPath: path) else { throw TagWriterError.writeFailed }
        return try write(changes, url: URL(fileURLWithPath: path), fileID: nil)
    }

    // MARK: dryRun

    public func dryRun(_ changes: TagChanges, fileID: Int64) throws -> [TagDiff] {
        guard !changes.isEmpty else { throw TagWriterError.emptyChanges }
        let (_, url) = try load(fileID)
        guard backendFor(url) != nil else { throw TagWriterError.unsupportedFormat }
        let before = try TagSnapshot.read(url)
        return Self.effective(changes, before: before, url: url).map {
            TagDiff(field: $0.field, oldValue: $0.old, newValue: $0.new, confidence: .high)
        }
    }

    // MARK: apply

    @discardableResult
    public func apply(_ changes: TagChanges, fileID: Int64) throws -> JournalEntry {
        guard !changes.isEmpty else { throw TagWriterError.emptyChanges }
        let (_, url) = try load(fileID)
        return try write(changes, url: url, fileID: fileID)
    }

    private func write(_ changes: TagChanges, url: URL, fileID: Int64?) throws -> JournalEntry {
        guard !changes.isEmpty else { throw TagWriterError.emptyChanges }
        guard let backend = backendFor(url) else { throw TagWriterError.unsupportedFormat }
        let recordPath = url.path

        let journalID = UUID()
        let before = try TagSnapshot.read(url)
        let planned = Self.effective(changes, before: before, url: url)
        let ext = url.pathExtension
        let work = url.deletingLastPathComponent()
            .appendingPathComponent(".wineup-\(UUID().uuidString)").appendingPathExtension(ext)
        var backup: URL?
        var swapped = false
        defer {
            try? FileManager.default.removeItem(at: work)
            if !swapped, let backup { backups.remove(backup) }
        }

        do {
            backup = try backups.backup(url, id: journalID)
            try backups.duplicate(url, to: work)
            try backend.write(changes, to: work)
            let after = try TagSnapshot.read(work)

            var expected = before
            for p in planned where p.field != "pictures" { expected.fields[p.field] = p.new }
            expected.pictures = Self.expectedPictures(changes, before: before, url: url)
            let wrong = after.differences(from: expected)
            guard wrong.isEmpty else { throw TagWriterError.verificationFailed(fields: wrong) }

            _ = try FileManager.default.replaceItemAt(url, withItemAt: work)
            swapped = true
            let stat = try FileStat.of(url)
            let tags = fileID == nil ? nil : try TagReader.read(url)
            let diffs = planned.map { TagDiff(field: $0.field, oldValue: $0.old, newValue: $0.new, confidence: .high) }
            let diffsJSON = try Self.encode(planned.map { DiffDTO(field: $0.field, old: $0.old, new: $0.new) })
            let beforeJSON = try Self.encode(before)
            let afterJSON = try Self.encode(after)
            let createdAt = Date()
            let backupPath = backup?.path
            try database.pool.write { db in
                try JournalRecord(id: journalID.uuidString, audioFileID: fileID, path: recordPath,
                                  backupPath: backupPath, diffsJSON: diffsJSON, status: "applied",
                                  afterInode: Int64(stat.inode), afterSize: stat.size,
                                  afterMtimeNs: stat.mtimeNs, createdAt: createdAt).insert(db)
                var beforeRec = TagSnapshotRecord(journalID: journalID.uuidString, kind: "before", json: beforeJSON)
                try beforeRec.insert(db)
                var afterRec = TagSnapshotRecord(journalID: journalID.uuidString, kind: "after", json: afterJSON)
                try afterRec.insert(db)
                if let fileID, let tags { try Self.updateFile(db, id: fileID, stat: stat, tags: tags, name: url) }
            }
            return JournalEntry(id: journalID, fileURL: url, diffs: diffs, createdAt: createdAt,
                                backupURL: backup)
        } catch {
            if !swapped {
                if let backup { backups.remove(backup) }
                backup = nil
                recordFailure(journalID: journalID, fileID: fileID, path: recordPath)
            }
            throw error
        }
    }

    private func recordFailure(journalID: UUID, fileID: Int64?, path: String) {
        try? database.pool.write { db in
            try JournalRecord(id: journalID.uuidString, audioFileID: fileID, path: path,
                              diffsJSON: "[]", status: "failed").insert(db)
        }
    }

    private static func updateFile(_ db: Database, id: Int64, stat: FileStat, tags: ScannedTags, name: URL) throws {
        try db.execute(sql: "UPDATE audio_file SET inode = ?, size = ?, mtime_ns = ?, duration = ? WHERE id = ?",
                       arguments: [Int64(stat.inode), stat.size, stat.mtimeNs, tags.duration, id])
        try CatalogWriter.ingest(db, audioFileID: id, tags: tags,
                                 fallbackTitle: name.deletingPathExtension().lastPathComponent)
    }

    private static func encode<T: Encodable>(_ value: T) throws -> String {
        let enc = JSONEncoder()
        enc.outputFormatting = [.sortedKeys]
        return String(decoding: try enc.encode(value), as: UTF8.self)
    }

    // MARK: undo

    public func undo(entryID: UUID) throws {
        let rec = try database.pool.read { try JournalRecord.fetchOne($0, key: entryID.uuidString) }
        guard let rec, rec.status == "applied", let backupPath = rec.backupPath,
              FileManager.default.fileExists(atPath: backupPath) else { throw TagWriterError.entryNotUndoable }
        let url = URL(fileURLWithPath: rec.path)
        let current = try FileStat.of(url)
        guard let i = rec.afterInode, let s = rec.afterSize, let m = rec.afterMtimeNs,
              current == FileStat(inode: UInt64(i), size: s, mtimeNs: m) else {
            throw TagWriterError.fileChangedSinceWrite
        }
        let work = url.deletingLastPathComponent()
            .appendingPathComponent(".wineup-undo-\(UUID().uuidString)").appendingPathExtension(url.pathExtension)
        defer { try? FileManager.default.removeItem(at: work) }
        try backups.duplicate(URL(fileURLWithPath: backupPath), to: work)
        _ = try FileManager.default.replaceItemAt(url, withItemAt: work)
        let stat = try FileStat.of(url)
        let fileID = rec.audioFileID
        let tags = fileID == nil ? nil : try TagReader.read(url)
        try database.pool.write { db in
            try db.execute(sql: "UPDATE journal SET status = 'undone', undone_at = ? WHERE id = ?",
                           arguments: [Date(), rec.id])
            if let fileID, let tags { try Self.updateFile(db, id: fileID, stat: stat, tags: tags, name: url) }
        }
    }

    public func journalEntries(fileID: Int64) throws -> [JournalEntry] {
        let rows = try database.pool.read {
            try JournalRecord.filter(Column("audio_file_id") == fileID)
                .order(Column("created_at").desc).fetchAll($0)
        }
        return rows.map { r in
            let dtos = (try? JSONDecoder().decode([DiffDTO].self, from: Data(r.diffsJSON.utf8))) ?? []
            return JournalEntry(
                id: UUID(uuidString: r.id) ?? UUID(), fileURL: URL(fileURLWithPath: r.path),
                diffs: dtos.map { TagDiff(field: $0.field, oldValue: $0.old, newValue: $0.new, confidence: .high) },
                createdAt: r.createdAt, backupURL: r.backupPath.map { URL(fileURLWithPath: $0) })
        }
    }
}
