import Foundation
import Testing
@testable import WineupLibrary

@Suite("Duplicadas e problemas ignorados")
struct DuplicatesTests {
    private func file(_ name: String, bitrate: Int?, cover: Bool = false, group: Int? = 1) -> FixerFile {
        var f = FixerFile(url: URL(fileURLWithPath: "/m/\(name)"), fields: ["title": "Song", "artist": "A"],
                          pictureCount: cover ? 1 : 0, duration: 200, duplicateGroup: group)
        f.tech.bitrate = bitrate
        return f
    }

    @Test func losslessThenBitrateThenCompleteness() {
        let mp3low = file("a.mp3", bitrate: 128), mp3high = file("b.mp3", bitrate: 320), flac = file("c.flac", bitrate: 900)
        let groups = DuplicateRanking.groups([mp3low, flac, mp3high, file("d.mp3", bitrate: 128, group: nil)])
        #expect(groups.count == 1)
        #expect(groups[0].files.map(\.url.lastPathComponent) == ["c.flac", "b.mp3", "a.mp3"])
        #expect(DuplicateRanking.reason(best: flac, other: mp3high) == "sem perda (FLAC)")
        #expect(DuplicateRanking.reason(best: file("x.mp3", bitrate: 128, cover: true), other: mp3low) == "tem capa")
    }

    @Test func ignoredIssuesPersist() throws {
        try withTempDirSync { dir in
            let store = IgnoredIssuesStore(directory: dir)
            try store.set([.missingLyrics, .missingGenre], for: "/m/a.mp3")
            #expect(IgnoredIssuesStore(directory: dir).all()["/m/a.mp3"] == [.missingLyrics, .missingGenre])
            try store.set([], for: "/m/a.mp3")
            #expect(store.all()["/m/a.mp3"] == nil)
        }
    }
}

private func withTempDirSync(_ body: (URL) throws -> Void) throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    try body(dir)
}
