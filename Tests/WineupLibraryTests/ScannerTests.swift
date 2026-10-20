import Foundation
import GRDB
import Testing
@testable import WineupLibrary

struct ScannerTests {
    @Test func tagReaderReadsWAV() async throws {
        try await withTempDir { dir in
            let url = dir.appendingPathComponent("a.wav")
            try WAVFixture.write(to: url)
            let tags = try TagReader.read(url)
            #expect((tags.duration ?? 0) > 0)
            #expect(tags.title == nil)
        }
    }

    @Test func tagReaderThrowsOnGarbage() async throws {
        try await withTempDir { dir in
            let url = dir.appendingPathComponent("bad.flac")
            try Data((0..<512).map { _ in UInt8.random(in: 0...255) }).write(to: url)
            #expect(throws: (any Error).self) { try TagReader.read(url) }
        }
    }

    @Test func enumeratorFiltersAndSkipsSymlinks() async throws {
        try await withTempDir { dir in
            let root = dir.appendingPathComponent("root", isDirectory: true)
            let outside = dir.appendingPathComponent("outside", isDirectory: true)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
            try WAVFixture.write(to: root.appendingPathComponent("a.wav"))
            try Data("x".utf8).write(to: root.appendingPathComponent("notes.txt"))
            try WAVFixture.write(to: root.appendingPathComponent(".wineup-hidden.wav"))
            try WAVFixture.write(to: outside.appendingPathComponent("b.wav"))
            try FileManager.default.createSymbolicLink(
                at: root.appendingPathComponent("link"), withDestinationURL: outside)
            try FileManager.default.createSymbolicLink(
                at: root.appendingPathComponent("c.wav"), withDestinationURL: outside.appendingPathComponent("b.wav"))
            let files = try FileEnumerator.enumerate(root: root, isCancelled: { false })
            #expect(files.count == 1)
            #expect(files.first?.path.hasSuffix("/a.wav") == true)
            #expect((files.first?.size ?? 0) > 0 && (files.first?.inode ?? 0) > 0)
        }
    }

    private func makeLibrary(_ dir: URL, count: Int) throws -> (LibraryDatabase, URL, UUID) {
        let db = try makeTempDatabase(in: dir)
        let music = dir.appendingPathComponent("Music", isDirectory: true)
        try FileManager.default.createDirectory(at: music, withIntermediateDirectories: true)
        for i in 0..<count {
            try WAVFixture.write(to: music.appendingPathComponent("t\(i).wav"), seconds: 0.02)
        }
        return (db, music, try LibraryRootStore(db: db).addRoot(music).id)
    }

    @Test func incrementalScanRereadsOnlyChanges() async throws {
        try await withTempDir { dir in
            let (db, music, id) = try makeLibrary(dir, count: 3)
            let scanner = Scanner(database: db)
            let p1 = try await scanner.scan(rootID: id, progress: { _ in })
            #expect(p1.enumerated == 3 && p1.read == 3 && p1.finished)
            let p2 = try await scanner.scan(rootID: id, progress: { _ in })
            #expect(p2.enumerated == 3 && p2.read == 0)
            try WAVFixture.write(to: music.appendingPathComponent("t1.wav"), seconds: 0.2)
            let p3 = try await scanner.scan(rootID: id, progress: { _ in })
            #expect(p3.read == 1)
            let n = try await db.pool.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM audio_file") }
            #expect(n == 3)
        }
    }

    @Test func streamEmitsProgress() async throws {
        try await withTempDir { dir in
            let (db, _, id) = try makeLibrary(dir, count: 3)
            var last: ScanProgress?
            for try await p in Scanner(database: db).scan(rootID: id) { last = p }
            #expect(last?.finished == true && last?.read == 3)
        }
    }

    @Test func cancellationLeavesConsistentDatabase() async throws {
        try await withTempDir { dir in
            let (db, _, id) = try makeLibrary(dir, count: 200)
            let scanner = Scanner(database: db, batchSize: 50)
            let task = Task {
                try await scanner.scan(rootID: id, progress: { p in
                    if p.read >= 50 { withUnsafeCurrentTask { $0?.cancel() } }
                })
            }
            await #expect(throws: CancellationError.self) { try await task.value }
            let partial = try await db.pool.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM audio_file") }!
            #expect(partial >= 50 && partial < 200)
            let bad = try await db.pool.read { try Int.fetchOne($0, sql: """
                SELECT COUNT(*) FROM audio_file a LEFT JOIN release_track r ON r.audio_file_id = a.id
                WHERE r.id IS NULL
                """) }
            #expect(bad == 0)
            let p = try await scanner.scan(rootID: id, progress: { _ in })
            #expect(p.read == 200 - partial)
            let total = try await db.pool.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM audio_file") }
            #expect(total == 200)
        }
    }
}
