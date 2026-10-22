import Foundation
import GRDB

public struct ScanProgress: Sendable, Equatable {
    public var enumerated: Int
    public var toRead: Int
    public var read: Int
    public var missing: Int
    public var moved: Int
    public var finished: Bool

    public init(enumerated: Int = 0, toRead: Int = 0, read: Int = 0, missing: Int = 0,
                moved: Int = 0, finished: Bool = false) {
        self.enumerated = enumerated; self.toRead = toRead; self.read = read
        self.missing = missing; self.moved = moved; self.finished = finished
    }
}

/// Varredura incremental em duas etapas: (1) enumeração por stat, (2) leitura de tags só
/// de arquivos novos/alterados, em lotes transacionais. Nunca apaga registros de arquivo.
public final class Scanner: Sendable {
    private let database: LibraryDatabase
    private let batchSize: Int

    /// Lê as tags do lote em paralelo (um arquivo por núcleo); a ordem do lote é preservada.
    /// A gravação no banco continua sequencial (um único escritor).
    static func readTags(_ batch: [(file: EnumeratedFile, existing: AudioFileRecord?)])
        -> [(EnumeratedFile, AudioFileRecord?, ScannedTags?, String?)] {
        let slots = UnsafeMutableBufferPointer<(ScannedTags?, String?)>.allocate(capacity: batch.count)
        slots.initialize(repeating: (nil, nil))
        defer { slots.deallocate() }
        DispatchQueue.concurrentPerform(iterations: batch.count) { i in
            do { slots[i] = (try TagReader.read(URL(fileURLWithPath: batch[i].file.path)), nil) }
            catch { slots[i] = (nil, "unreadable") }
        }
        return batch.indices.map { (batch[$0].file, batch[$0].existing, slots[$0].0, slots[$0].1) }
    }

    public init(database: LibraryDatabase, batchSize: Int = 500) {
        self.database = database
        self.batchSize = max(1, batchSize)
    }

    public func scan(rootID: UUID) -> AsyncThrowingStream<ScanProgress, Error> {
        AsyncThrowingStream { continuation in
            let task = Task.detached(priority: .utility) { [self] in
                do {
                    _ = try await scan(rootID: rootID, progress: { continuation.yield($0) })
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    public func scan(rootID: UUID, progress: @Sendable (ScanProgress) -> Void) async throws -> ScanProgress {
        let pool = database.pool
        guard let root = try await pool.read({ try LibraryRootRecord
            .filter(Column("uuid") == rootID.uuidString).fetchOne($0) }),
              let rootRowID = root.id else { throw LibraryError.rootNotFound }

        let rootURL = URL(fileURLWithPath: root.path, isDirectory: true)
        var isDir: ObjCBool = false
        let reachable = FileManager.default.fileExists(atPath: root.path, isDirectory: &isDir)
            && isDir.boolValue && FileManager.default.isReadableFile(atPath: root.path)
        guard reachable else {
            // Volume desmontado/pasta ausente: offline, sem marcar nada como ausente.
            try await pool.write { try $0.execute(sql: "UPDATE library_root SET online = 0 WHERE id = ?",
                                                  arguments: [rootRowID]) }
            let done = ScanProgress(finished: true)
            progress(done)
            return done
        }
        try await pool.write { try $0.execute(sql: "UPDATE library_root SET online = 1 WHERE id = ?",
                                              arguments: [rootRowID]) }

        // Etapa 1
        let files = try FileEnumerator.enumerate(root: rootURL, isCancelled: { Task.isCancelled })
        try Task.checkCancellation()
        let known = try await pool.read { db in
            try AudioFileRecord.filter(Column("root_id") == rootRowID).fetchAll(db)
        }
        let knownByPath = Dictionary(known.map { ($0.path, $0) }, uniquingKeysWith: { a, _ in a })
        let enumeratedPaths = Set(files.map(\.path))

        var unchanged: [Int64] = []
        var toRead: [(file: EnumeratedFile, existing: AudioFileRecord?)] = []
        var candidates: [EnumeratedFile] = []
        for f in files {
            if let rec = knownByPath[f.path] {
                if rec.status == FileStatus.present.rawValue, rec.size == f.size,
                   rec.mtimeNs == f.mtimeNs, rec.inode == Int64(bitPattern: f.inode) {
                    unchanged.append(rec.id!)
                } else {
                    toRead.append((f, rec))
                }
            } else {
                candidates.append(f)
            }
        }

        // Movidos: mesmo (inode, size) entre registros da raiz que sumiram do disco.
        struct Key: Hashable { let inode: Int64; let size: Int64 }
        var orphans: [Key: [AudioFileRecord]] = [:]
        for rec in known where !enumeratedPaths.contains(rec.path) {
            if let ino = rec.inode { orphans[Key(inode: ino, size: rec.size), default: []].append(rec) }
        }
        var candidatesByKey: [Key: Int] = [:]
        for c in candidates { candidatesByKey[Key(inode: Int64(bitPattern: c.inode), size: c.size), default: 0] += 1 }
        var movedPairs: [(file: EnumeratedFile, record: AudioFileRecord)] = []
        var movedIDs = Set<Int64>()
        for c in candidates {
            let key = Key(inode: Int64(bitPattern: c.inode), size: c.size)
            if let recs = orphans[key], recs.count == 1, candidatesByKey[key] == 1 {
                movedPairs.append((c, recs[0])); movedIDs.insert(recs[0].id!)
            } else {
                toRead.append((c, nil))
            }
        }
        // Movido que estava ausente precisa voltar ao índice de busca.
        for pair in movedPairs where pair.record.status == FileStatus.missing.rawValue {
            toRead.append((pair.file, pair.record))
        }
        let rereadMoved = Set(movedPairs.filter { $0.record.status == FileStatus.missing.rawValue }
            .map { $0.record.id! })

        var state = ScanProgress(enumerated: files.count, toRead: toRead.count,
                                 moved: movedPairs.count)
        let now = Date()
        let volume = root.volumeUUID

        // Gravações de manutenção (last_seen, movidos) em transações curtas.
        for chunk in stride(from: 0, to: unchanged.count, by: 1000).map({ Array(unchanged[$0..<min($0 + 1000, unchanged.count)]) }) {
            try Task.checkCancellation()
            try await pool.write { db in
                let st = try db.cachedStatement(sql: "UPDATE audio_file SET last_seen_at = ? WHERE id = ?")
                for id in chunk { try st.execute(arguments: [now, id]) }
            }
        }
        let moves = movedPairs
        let rereadSet = rereadMoved
        try await pool.write { db in
            for (f, rec) in moves {
                let status = rereadSet.contains(rec.id!) ? rec.status : FileStatus.present.rawValue
                try db.execute(sql: """
                    UPDATE audio_file SET path = ?, mtime_ns = ?, inode = ?, status = ?,
                    missing_since = CASE WHEN ? = 'present' THEN NULL ELSE missing_since END,
                    last_seen_at = ? WHERE id = ?
                    """, arguments: [f.path, f.mtimeNs, Int64(bitPattern: f.inode), status, status, now, rec.id!])
            }
        }
        progress(state)

        // Etapa 2: leitura de tags em lotes
        let size = batchSize
        for start in stride(from: 0, to: toRead.count, by: size) {
            try Task.checkCancellation()
            let batch = Array(toRead[start..<min(start + size, toRead.count)])
            let results = Self.readTags(batch)
            try await pool.write { db in
                for (f, existing, tags, readError) in results {
                    var rec = existing ?? AudioFileRecord(rootID: rootRowID, path: f.path)
                    rec.path = f.path
                    rec.volumeUUID = volume
                    rec.inode = Int64(bitPattern: f.inode)
                    rec.size = f.size
                    rec.mtimeNs = f.mtimeNs
                    rec.status = FileStatus.present.rawValue
                    rec.missingSince = nil
                    rec.lastSeenAt = now
                    rec.format = (f.path as NSString).pathExtension.lowercased()
                    rec.readError = readError
                    if let d = tags?.duration { rec.duration = d }
                    if rec.id == nil { try rec.insert(db) } else { try rec.update(db) }
                    if let tags {
                        let fallback = ((f.path as NSString).lastPathComponent as NSString).deletingPathExtension
                        try CatalogWriter.ingest(db, audioFileID: rec.id!, tags: tags, fallbackTitle: fallback)
                    }
                }
            }
            state.read += batch.count
            progress(state)
        }

        // Ausentes: nunca DELETE; só marca e tira do índice de busca.
        try Task.checkCancellation()
        let seen = Set(unchanged).union(movedIDs).union(toRead.compactMap { $0.existing?.id })
        let vanished = known.filter { $0.status == FileStatus.present.rawValue && !seen.contains($0.id!) }
            .compactMap(\.id)
        if !vanished.isEmpty {
            try await pool.write { db in
                for id in vanished {
                    try db.execute(sql: "UPDATE audio_file SET status = 'missing', missing_since = ? WHERE id = ?",
                                   arguments: [now, id])
                    try CatalogWriter.removeFromIndex(db, audioFileID: id)
                }
            }
        }
        state.missing = vanished.count
        try await pool.write { try $0.execute(sql: "UPDATE library_root SET last_scan_at = ? WHERE id = ?",
                                              arguments: [now, rootRowID]) }
        state.finished = true
        progress(state)
        return state
    }
}
