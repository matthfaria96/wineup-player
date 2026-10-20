import Foundation
import GRDB
import Testing
import WineupCore
@testable import WineupLibrary

@Suite("SAFE-02: desfazer pelo diário")
struct TagWriterUndoTests {
    @Test(arguments: [FormatCase.flac, .mp3v4, .m4aAAC])
    func undoRestoresIdenticalBytes(_ format: FormatCase) async throws {
        try await withTempDir { dir in
            let h = try await WriterHarness.make(dir) { try format.make($0) }
            let sha = try WriterHarness.sha(h.file)
            let oldTitle = try TagSnapshot.read(h.file).fields["title"]
            let w = h.writer()
            let entry = try w.apply(TagChanges(title: "Zebra Unico"), fileID: h.fileID)
            let search = SearchService(database: h.db)
            #expect(try await search.search("Zebra").count == 1)

            try w.undo(entryID: entry.id)
            #expect(try WriterHarness.sha(h.file) == sha)
            #expect(try TagSnapshot.read(h.file).fields["title"] == oldTitle)
            let row = try #require(try await h.journalRows().first)
            #expect(row.status == "undone" && row.undoneAt != nil)
            let stat = try FileStat.of(h.file)
            let f = try #require(try await h.db.pool.read { try AudioFileRecord.fetchOne($0, key: h.fileID) })
            #expect(f.inode == Int64(stat.inode) && f.size == stat.size && f.mtimeNs == stat.mtimeNs)
            #expect(try await search.search("Zebra").isEmpty)
            #expect(h.leftovers.isEmpty)
        }
    }

    @Test func secondUndoAndFailedEntryAreRefused() async throws {
        try await withTempDir { dir in
            let h = try await WriterHarness.make(dir) { try Fixtures.flac($0) }
            let w = h.writer()
            let entry = try w.apply(TagChanges(title: "A"), fileID: h.fileID)
            try w.undo(entryID: entry.id)
            #expect(throws: TagWriterError.entryNotUndoable) { try w.undo(entryID: entry.id) }

            let chaos = h.writer(backend: { ChaosBackend(inner: TagBackends.backend(for: $0)!) })
            _ = try? chaos.apply(TagChanges(title: "B"), fileID: h.fileID)
            let failed = try #require(try await h.journalRows().first { $0.status == "failed" })
            #expect(throws: TagWriterError.entryNotUndoable) { try w.undo(entryID: UUID(uuidString: failed.id)!) }
        }
    }

    @Test func modifiedFileIsNotTouchedByUndo() async throws {
        try await withTempDir { dir in
            let h = try await WriterHarness.make(dir) { try Fixtures.flac($0) }
            let w = h.writer()
            let entry = try w.apply(TagChanges(title: "A"), fileID: h.fileID)
            let handle = try FileHandle(forWritingTo: h.file)
            try handle.seekToEnd(); try handle.write(contentsOf: Data([0])); try handle.close()
            let sha = try WriterHarness.sha(h.file)
            #expect(throws: TagWriterError.fileChangedSinceWrite) { try w.undo(entryID: entry.id) }
            #expect(try WriterHarness.sha(h.file) == sha)
        }
    }

    @Test func missingBackupLeavesFileIntact() async throws {
        try await withTempDir { dir in
            let h = try await WriterHarness.make(dir) { try Fixtures.flac($0) }
            let w = h.writer()
            let entry = try w.apply(TagChanges(title: "A"), fileID: h.fileID)
            try FileManager.default.removeItem(at: h.backupsDir)
            let sha = try WriterHarness.sha(h.file)
            #expect(throws: (any Error).self) { try w.undo(entryID: entry.id) }
            #expect(try WriterHarness.sha(h.file) == sha)
        }
    }

    @Test func journalEntriesAreNewestFirst() async throws {
        try await withTempDir { dir in
            let h = try await WriterHarness.make(dir) { try Fixtures.flac($0) }
            let w = h.writer()
            let first = try w.apply(TagChanges(title: "A"), fileID: h.fileID)
            try await Task.sleep(nanoseconds: 20_000_000)
            let second = try w.apply(TagChanges(title: "B"), fileID: h.fileID)
            #expect(try w.journalEntries(fileID: h.fileID).map(\.id) == [second.id, first.id])
        }
    }
}
