import Foundation
import Testing
@testable import WineupCore

private func sample() -> [Track] {
    [
        Track(artist: "A", title: "Zeta", duration: 10, mark: .red),
        Track(artist: "B", title: "Alfa", duration: 20, mark: .blue),
        Track(artist: "C", title: "Mu", duration: 30, mark: .red),
    ]
}

@Test func sameDataGivesDifferentIDs() {
    let a = Track(artist: "A", title: "T", duration: 1, mark: nil)
    let b = Track(artist: "A", title: "T", duration: 1, mark: nil)
    #expect(a.id != b.id)
}

@Test func reorderFilterSortKeepIDs() {
    let tracks = sample()
    let ids = Set(tracks.map(\.id))
    #expect(Set(tracks.reversed().map(\.id)) == ids)
    #expect(Set(tracks.sorted { $0.title < $1.title }.map(\.id)) == ids)
    let red = tracks.filter { $0.mark == .red }
    #expect(Set(red.map(\.id)) == [tracks[0].id, tracks[2].id])
}

@Test func removingKeepsOtherIDs() {
    let tracks = sample()
    let result = TrackList.removing(tracks[1].id, from: tracks)
    #expect(result.map(\.id) == [tracks[0].id, tracks[2].id])
    #expect(tracks.count == 3)
}

@Test func neighborWrapsAndHandlesMissing() {
    let tracks = sample()
    #expect(TrackList.neighbor(of: tracks[2].id, offset: 1, in: tracks)?.id == tracks[0].id)
    #expect(TrackList.neighbor(of: tracks[0].id, offset: -1, in: tracks)?.id == tracks[2].id)
    #expect(TrackList.neighbor(of: TrackID(), offset: 1, in: tracks) == nil)
}

@Test func clockFormats() {
    #expect(Clock.format(65) == "1:05")
    #expect(Clock.format(3661) == "1:01:01")
    #expect(Clock.format(-3) == "0:00")
}

@Test func seedIsDeterministic() {
    let id = TrackID(UUID(uuidString: "01020304-0000-0000-0000-000000000000")!)
    #expect(id.seed == 0x0102)
}
