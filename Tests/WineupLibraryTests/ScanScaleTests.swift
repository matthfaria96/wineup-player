import Foundation
import GRDB
import Testing
@testable import WineupLibrary

private actor TickRecorder {
    private(set) var maxGap: Double = 0
    func record(_ gap: Double) { maxGap = max(maxGap, gap) }
}

struct ScanScaleTests {
    @Test(.timeLimit(.minutes(2)))
    func scansTenThousandEmptyFilesWithoutBlockingMain() async throws {
        try await withTempDir { dir in
            let music = dir.appendingPathComponent("Music", isDirectory: true)
            for d in 0..<100 {
                let sub = music.appendingPathComponent("d\(d)", isDirectory: true)
                try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
                for f in 0..<100 {
                    #expect(FileManager.default.createFile(atPath: sub.appendingPathComponent("f\(f).mp3").path, contents: nil))
                }
            }
            let t0 = Date()
            let listed = try FileEnumerator.enumerate(root: music, isCancelled: { false })
            #expect(listed.count == 10_000)
            #expect(Date().timeIntervalSince(t0) < 3)

            let db = try makeTempDatabase(in: dir)
            let id = try LibraryRootStore(db: db).addRoot(music).id
            let scanner = Scanner(database: db)

            let recorder = TickRecorder()
            let ticker = Task { @MainActor in
                var last = Date()
                for _ in 0..<20 {
                    try? await Task.sleep(nanoseconds: 50_000_000)
                    let now = Date()
                    await recorder.record(now.timeIntervalSince(last) - 0.05)
                    last = now
                }
            }
            let first = try await Task { try await scanner.scan(rootID: id, progress: { _ in }) }.value
            await ticker.value
            #expect(first.enumerated == 10_000)
            let rows = try await db.pool.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM audio_file") }
            #expect(rows == 10_000)
            #expect(await recorder.maxGap < 0.25)

            let t1 = Date()
            let second = try await scanner.scan(rootID: id, progress: { _ in })
            #expect(second.toRead == 0 && second.read == 0)
            #expect(Date().timeIntervalSince(t1) < 3)
        }
    }
}
