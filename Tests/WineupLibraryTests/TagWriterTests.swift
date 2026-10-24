import Foundation
import CryptoKit
import GRDB
import Testing
import WineupCore
@testable import WineupLibrary

/// Biblioteca descartável: tudo dentro do diretório temporário do teste.
struct WriterHarness {
    let db: LibraryDatabase
    let music: URL
    let backupsDir: URL
    let file: URL
    let fileID: Int64

    static func make(_ dir: URL, fixture: (URL) throws -> URL) async throws -> WriterHarness {
        let db = try makeTempDatabase(in: dir)
        let music = dir.appendingPathComponent("Music", isDirectory: true)
        try FileManager.default.createDirectory(at: music, withIntermediateDirectories: true)
        let file = try fixture(music)
        let root = try LibraryRootStore(db: db).addRoot(music)
        _ = try await Scanner(database: db).scan(rootID: root.id, progress: { _ in })
        let id = try await db.pool.read { try Int64.fetchOne($0, sql: "SELECT id FROM audio_file LIMIT 1") }
        return WriterHarness(db: db, music: music, backupsDir: dir.appendingPathComponent("Backups"),
                             file: file.resolvingSymlinksInPath(), fileID: try #require(id))
    }

    func writer(clone: (@Sendable (String, String) -> Int32)? = nil,
                available: (@Sendable (URL) throws -> Int64)? = nil,
                backend: (@Sendable (URL) -> TagBackend?)? = nil) -> TagWriter {
        let store = BackupStore(directory: backupsDir,
                                clone: clone ?? { clonefile($0, $1, 0) },
                                availableBytes: available ?? BackupStore.systemAvailableBytes)
        return TagWriter(database: db, backups: store, backendFor: backend ?? { TagBackends.backend(for: $0) })
    }

    static func sha(_ url: URL) throws -> String {
        SHA256.hash(data: try Data(contentsOf: url)).map { String(format: "%02x", $0) }.joined()
    }

    var leftovers: [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: music.path)) ?? []).filter { $0.hasPrefix(".wineup-") }
    }

    func journalRows() async throws -> [JournalRecord] { try await db.pool.read { try JournalRecord.fetchAll($0) } }
}

struct ChaosBackend: TagBackend {
    let inner: TagBackend
    func write(_ changes: TagChanges, to url: URL) throws {
        try inner.write(changes, to: url)
        try inner.write(TagChanges(artist: "Sabotado"), to: url)
    }
}

struct ThrowingBackend: TagBackend {
    func write(_ changes: TagChanges, to url: URL) throws { throw TagBackendError.writeFailed(code: 1) }
}

@Suite("SAFE-01: TagWriter.apply")
struct TagWriterTests {
    @Test(arguments: [FormatCase.flac, .mp3v3, .wav])
    func applyWritesBacksUpAndJournals(_ format: FormatCase) async throws {
        try await withTempDir { dir in
            let h = try await WriterHarness.make(dir) { try format.make($0) }
            let originalSHA = try WriterHarness.sha(h.file)
            let entry = try h.writer().apply(TagChanges(title: "Novo"), fileID: h.fileID)

            #expect(try TagSnapshot.read(h.file).fields["title"] == "Novo")
            let backup = try #require(entry.backupURL)
            #expect(try WriterHarness.sha(backup) == originalSHA)
            #expect(entry.diffs.map(\.field) == ["title"])

            let rows = try await h.journalRows()
            #expect(rows.count == 1 && rows[0].status == "applied")
            #expect(rows[0].diffsJSON.contains("title"))
            let snaps = try await h.db.pool.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM tag_snapshot") }
            #expect(snaps == 2)
            let stat = try FileStat.of(h.file)
            let f = try #require(try await h.db.pool.read { try AudioFileRecord.fetchOne($0, key: h.fileID) })
            #expect(f.inode == Int64(stat.inode) && f.size == stat.size && f.mtimeNs == stat.mtimeNs)
            #expect(h.leftovers.isEmpty)
            if format == .mp3v3 { #expect(TagProbe.id3Version(h.file) == 3) }
        }
    }

    @Test func verificationFailureLeavesOriginalIntact() async throws {
        try await withTempDir { dir in
            let h = try await WriterHarness.make(dir) { try Fixtures.flac($0) }
            let sha = try WriterHarness.sha(h.file)
            let w = h.writer(backend: { ChaosBackend(inner: TagBackends.backend(for: $0)!) })
            #expect(throws: TagWriterError.verificationFailed(fields: ["artist"])) {
                try w.apply(TagChanges(title: "Novo"), fileID: h.fileID)
            }
            #expect(try WriterHarness.sha(h.file) == sha)
            #expect(h.leftovers.isEmpty)
            let rows = try await h.journalRows()
            #expect(rows.count == 1 && rows[0].status == "failed" && rows[0].backupPath == nil)
            let backups = (try? FileManager.default.contentsOfDirectory(atPath: h.backupsDir.path)) ?? []
            #expect(backups.isEmpty)
        }
    }

    @Test func throwingBackendLeavesNoTraces() async throws {
        try await withTempDir { dir in
            let h = try await WriterHarness.make(dir) { try Fixtures.flac($0) }
            let sha = try WriterHarness.sha(h.file)
            let w = h.writer(backend: { _ in ThrowingBackend() })
            #expect(throws: (any Error).self) { try w.apply(TagChanges(title: "X"), fileID: h.fileID) }
            #expect(try WriterHarness.sha(h.file) == sha)
            #expect(h.leftovers.isEmpty)
        }
    }

    @Test func outsideRootsIsRefused() async throws {
        try await withTempDir { dir in
            let h = try await WriterHarness.make(dir) { try Fixtures.flac($0) }
            let sha = try WriterHarness.sha(h.file)
            let other = dir.appendingPathComponent("Other", isDirectory: true)
            try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)
            let moved = other.appendingPathComponent("a.flac")
            try FileManager.default.moveItem(at: h.file, to: moved)
            try await h.db.pool.write {
                try $0.execute(sql: "UPDATE audio_file SET path = ? WHERE id = ?", arguments: [moved.path, h.fileID])
            }
            #expect(throws: LibraryError.outsideRoots) {
                try h.writer().apply(TagChanges(title: "X"), fileID: h.fileID)
            }
            #expect(try WriterHarness.sha(moved) == sha)
        }
    }

    @Test func insufficientSpaceTouchesNothing() async throws {
        try await withTempDir { dir in
            let h = try await WriterHarness.make(dir) { try Fixtures.flac($0) }
            let sha = try WriterHarness.sha(h.file)
            let w = h.writer(clone: { _, _ in errno = ENOTSUP; return -1 }, available: { _ in 0 })
            #expect(throws: TagWriterError.insufficientSpace) {
                try w.apply(TagChanges(title: "X"), fileID: h.fileID)
            }
            #expect(try WriterHarness.sha(h.file) == sha)
            #expect(h.leftovers.isEmpty)
        }
    }

    @Test func emptyChangesAndUnsupportedFormat() async throws {
        try await withTempDir { dir in
            let h = try await WriterHarness.make(dir) { try Fixtures.flac($0) }
            let sha = try WriterHarness.sha(h.file)
            #expect(throws: TagWriterError.emptyChanges) { try h.writer().apply(TagChanges(), fileID: h.fileID) }
            let w = h.writer(backend: { _ in nil })
            #expect(throws: TagWriterError.unsupportedFormat) {
                try w.apply(TagChanges(title: "X"), fileID: h.fileID)
            }
            #expect(try WriterHarness.sha(h.file) == sha)
            #expect(try await h.journalRows().isEmpty)
        }
    }

    @Test func backupFallsBackToCopyOnNotSupported() async throws {
        try await withTempDir { dir in
            let src = try Fixtures.wav(dir)
            let store = BackupStore(directory: dir.appendingPathComponent("B"),
                                    clone: { _, _ in errno = EXDEV; return -1 },
                                    availableBytes: { _ in Int64.max })
            let b = try store.backup(src, id: UUID())
            #expect(try WriterHarness.sha(b) == WriterHarness.sha(src))
            let hard = BackupStore(directory: dir.appendingPathComponent("C"),
                                   clone: { _, _ in errno = EACCES; return -1 })
            #expect(throws: TagWriterError.writeFailed) { try hard.backup(src, id: UUID()) }
        }
    }

    @Test func cloneWorksOnApfs() async throws {
        try await withTempDir { dir in
            let src = try Fixtures.wav(dir)
            let b = try BackupStore(directory: dir.appendingPathComponent("B")).backup(src, id: UUID())
            #expect(try WriterHarness.sha(b) == WriterHarness.sha(src))
        }
    }
}
