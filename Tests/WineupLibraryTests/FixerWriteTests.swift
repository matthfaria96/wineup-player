import Foundation
import Testing
@testable import WineupLibrary

/// PNG 1x1 válido (bytes reais, para conferir o hash depois de gravar).
let tinyPNG = Data(base64Encoded:
    "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==")!

@Suite("Gerenciador de metadados: gravação de capa, compositor e comentário")
struct FixerWriteTests {
    @Test(arguments: [FormatCase.flac, .mp3v3, .mp3v4, .m4aAAC, .opus, .wav])
    func coverComposerCommentRoundTrip(_ format: FormatCase) async throws {
        try await withTempDir { dir in
            let h = try await WriterHarness.make(dir) { try format.make($0) }
            let changes = TagChanges(composer: "Nils Frahm", comment: "Visit bandcamp",
                                     cover: CoverImage(data: tinyPNG, mimeType: "image/png"))
            let entry = try h.writer().apply(changes, fileID: h.fileID)
            let after = try TagSnapshot.read(h.file)
            #expect(after.fields["composer"] == "Nils Frahm")
            #expect(after.fields["comment"] == "Visit bandcamp")
            #expect(after.pictures.count == 1)
            #expect(after.pictures[0].byteCount == tinyPNG.count)
            #expect(entry.diffs.map(\.field).contains("pictures"))
            try h.writer().undo(entryID: entry.id)
            #expect(try TagSnapshot.read(h.file).fields["composer"] == nil)
        }
    }

    @Test func writesFileOutsideLibraryWithBackupAndUndo() async throws {
        try await withTempDir { dir in
            let h = try await WriterHarness.make(dir) { try FormatCase.flac.make($0) }
            let loose = dir.appendingPathComponent("Loose", isDirectory: true)
            try FileManager.default.createDirectory(at: loose, withIntermediateDirectories: true)
            let file = try FormatCase.flac.make(loose)
            let original = try WriterHarness.sha(file)
            let entry = try h.writer().apply(TagChanges(title: "Fora"), url: file)
            #expect(try TagSnapshot.read(file).fields["title"] == "Fora")
            #expect(try WriterHarness.sha(#require(entry.backupURL)) == original)
            let rows = try await h.journalRows()
            #expect(rows.contains { $0.path == file.path && $0.audioFileID == nil && $0.status == "applied" })
            try h.writer().undo(entryID: entry.id)
            #expect(try WriterHarness.sha(file) == original)
        }
    }

    @Test func urlWriteUsesLibraryRecordWhenIndexed() async throws {
        try await withTempDir { dir in
            let h = try await WriterHarness.make(dir) { try FormatCase.flac.make($0) }
            _ = try h.writer().apply(TagChanges(album: "Indexado"), url: h.file)
            let rows = try await h.journalRows()
            #expect(rows.first?.audioFileID == h.fileID)
            let album = try await h.db.pool.read { try String.fetchOne($0, sql: "SELECT title FROM release LIMIT 1") }
            #expect(album == "Indexado")
        }
    }

    @Test func lyricsFileIsWrittenBesideAudioAndNotOverwritten() async throws {
        try await withTempDir { dir in
            let audio = dir.appendingPathComponent("01 Song.flac")
            let lrc = try LyricsFileWriter.write("[00:01.00] Olá", for: audio, replace: false)
            #expect(lrc.lastPathComponent == "01 Song.lrc")
            #expect(throws: LyricsFileWriter.WriteError.alreadyExists) {
                try LyricsFileWriter.write("[00:02.00] outra", for: audio, replace: false)
            }
            _ = try LyricsFileWriter.write("[00:02.00] outra", for: audio, replace: true)
            #expect(try String(contentsOf: lrc, encoding: .utf8).contains("outra"))
            #expect(throws: LyricsFileWriter.WriteError.empty) { try LyricsFileWriter.write("  ", for: audio, replace: true) }
        }
    }

    @Test func analyzerFlagsMissingFieldsAndLyrics() async throws {
        try await withTempDir { dir in
            let url = try FormatCase.flac.make(dir)
            let files = await FolderAnalyzer.analyze(FolderAnalyzer.audioFiles(in: dir))
            let f = try #require(files.first { $0.url.lastPathComponent == url.lastPathComponent })
            #expect(f.issues.contains(.missingLyrics))
            _ = try LyricsFileWriter.write("[00:01.00] x", for: url, replace: false)
            #expect(!FolderAnalyzer.read(url).issues.contains(.missingLyrics))
        }
    }
}
