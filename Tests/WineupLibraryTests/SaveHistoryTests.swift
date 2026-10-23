import Foundation
import Testing
@testable import WineupLibrary

@Suite("Desfazer em lote")
struct SaveHistoryTests {
    @Test func undoRestoresTagsAndLyricsOfTheWholeBatch() async throws {
        try await withTempDir { dir in
            let h = try await WriterHarness.make(dir) { try FormatCase.flac.make($0) }
            let store = SaveHistoryStore(directory: dir.appendingPathComponent("Support"))
            let writer = h.writer()
            let originalSHA = try WriterHarness.sha(h.file)
            let lrc = h.file.deletingPathExtension().appendingPathExtension("lrc")
            try "[00:01.00] antiga".write(to: lrc, atomically: true, encoding: .utf8)

            // Gravação: tags + troca do .lrc (com cópia do antigo).
            let entry = try writer.apply(TagChanges(title: "Nova", cover: CoverImage(data: tinyPNG, mimeType: "image/png")), url: h.file)
            let backup = try store.backupLyrics(of: lrc)
            _ = try LyricsFileWriter.write("[00:01.00] nova", for: h.file, replace: true)
            let batch = SaveBatch(folder: h.music.path, items: [
                .init(path: h.file.path, journalID: entry.id, lyricsBackup: backup, wroteLyrics: true)])
            try store.add(batch)
            #expect(store.batches().first?.id == batch.id)

            let result = BatchUndo.undo(batch, writer: writer)
            try store.markUndone(batch.id)
            #expect(result == BatchUndo.Result(restored: 1, failed: []))
            #expect(try WriterHarness.sha(h.file) == originalSHA)
            #expect(try String(contentsOf: lrc, encoding: .utf8).contains("antiga"))
            #expect(store.batches().first?.undone == true)
        }
    }

    @Test func createdLyricsGoToTrashOnUndo() async throws {
        try await withTempDir { dir in
            let h = try await WriterHarness.make(dir) { try FormatCase.flac.make($0) }
            let lrc = try LyricsFileWriter.write("[00:01.00] x", for: h.file, replace: false)
            let batch = SaveBatch(folder: h.music.path, items: [.init(path: h.file.path, wroteLyrics: true)])
            #expect(BatchUndo.undo(batch, writer: h.writer(), remove: { try FileManager.default.removeItem(at: $0) }).restored == 1)
            #expect(!FileManager.default.fileExists(atPath: lrc.path))
        }
    }
}
