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

@Test func clockFormats() {
    #expect(Clock.format(65) == "1:05")
    #expect(Clock.format(3661) == "1:01:01")
    #expect(Clock.format(-3) == "0:00")
}

@Test func seedIsDeterministic() {
    let id = TrackID(UUID(uuidString: "01020304-0000-0000-0000-000000000000")!)
    #expect(id.seed == 0x0102)
}

@Test func matchingFiltersByArtistAndTitleIgnoringCase() {
    let tracks = [Track(artist: "Banda", title: "Faixa 12", duration: 1, mark: nil),
                  Track(artist: "Outra", title: "Nada", duration: 1, mark: nil),
                  Track(artist: "FAIXA", title: "x", duration: 1, mark: nil)]
    #expect(TrackList.matching("faixa", in: tracks).map(\.title) == ["Faixa 12", "x"])
    #expect(TrackList.matching("  ", in: tracks).isEmpty)
    #expect(TrackList.matching("banda - faixa", in: tracks).count == 1)
}

@Test func loadBatchesStartSmallAndGrowToALimit() {
    #expect(LoadBatches.size(afterDelivered: 0) == 100)
    #expect(LoadBatches.size(afterDelivered: 100) == 100)
    #expect(LoadBatches.size(afterDelivered: 200) == 200)
    #expect(LoadBatches.size(afterDelivered: 1500) == 1500)
    #expect(LoadBatches.size(afterDelivered: 9000) == 2000)
    var delivered = 0, batches = 0
    while delivered < 5000 { delivered += LoadBatches.size(afterDelivered: delivered); batches += 1 }
    #expect(batches == 7)
}
