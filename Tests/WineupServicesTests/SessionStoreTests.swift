import Foundation
import Testing
import WineupCore
@testable import WineupLibrary
@testable import WineupServices

private func entry(_ n: Int) -> QueueEntry {
    QueueEntry(fileID: Int64(n), url: URL(fileURLWithPath: "/tmp/s\(n).mp3"), title: "T\(n)", artist: "A", duration: 5)
}

@Test func sessionRoundTripAcrossInstances() async throws {
    try await withTempDir { dir in
        let snap = SessionSnapshot(entries: [entry(0), entry(1)], currentIndex: 1, position: 12.5,
                                   repeatMode: .all, shuffled: true, seed: 77)
        try SessionStore(db: try makeTempDatabase(in: dir)).save(snap)
        let loaded = SessionStore(db: try makeTempDatabase(in: dir)).load()
        #expect(loaded == snap)
    }
}

@Test func corruptedJSONLoadsNil() async throws {
    try await withTempDir { dir in
        let db = try makeTempDatabase(in: dir)
        try SettingsStore(db: db).set(SettingsStore.Keys.session, "{not json")
        #expect(SessionStore(db: db).load() == nil)
    }
}

@Test func outOfRangeIndexBecomesNil() async throws {
    try await withTempDir { dir in
        let db = try makeTempDatabase(in: dir)
        let snap = SessionSnapshot(entries: [entry(0)], currentIndex: 5, position: -3,
                                   repeatMode: .off, shuffled: false, seed: 0)
        try SessionStore(db: db).save(snap)
        let loaded = SessionStore(db: db).load()
        #expect(loaded?.currentIndex == nil)
        #expect(loaded?.position == 0)
    }
}

@Test func restorableDropsMissingFiles() {
    let snap = SessionSnapshot(entries: [entry(0), entry(1), entry(2)], currentIndex: 2, position: 9,
                               repeatMode: .off, shuffled: false, seed: 0)
    let kept = snap.restorable { $0.lastPathComponent != "s0.mp3" }
    #expect(kept.entries.count == 2)
    #expect(kept.currentIndex == 1)
    let lost = snap.restorable { $0.lastPathComponent != "s2.mp3" }
    #expect(lost.currentIndex == nil)
    #expect(lost.position == 0)
}

@Test func settingsBoolDefaultsAndPrefix() async throws {
    try await withTempDir { dir in
        let s = SettingsStore(db: try makeTempDatabase(in: dir))
        #expect(try s.bool("x.flag", default: true) == true)
        try s.setBool("x.flag", false)
        #expect(try s.bool("x.flag", default: true) == false)
        try s.set("x.other", "v")
        #expect(try s.all(prefix: "x.").count == 2)
    }
}

@Test func fixtureInsertsTrack() async throws {
    try await withTempDir { dir in
        let db = try makeTempDatabase(in: dir)
        let id = try ServicesFixtures.insertTrack(db: db, path: "/tmp/a.mp3", title: "t", artist: "a", album: "b", duration: 3)
        #expect(id > 0)
    }
}
