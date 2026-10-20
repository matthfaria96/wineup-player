import Testing
@testable import WineupCore

private let tracks = [
    Track(artist: "A", title: "1", duration: 1, mark: nil),
    Track(artist: "B", title: "2", duration: 1, mark: nil),
    Track(artist: "C", title: "3", duration: 1, mark: nil),
]

@Test func nextIsNeighbor() {
    #expect(NextTrackPlanner.next(after: tracks[0].id, in: tracks)?.id == tracks[1].id)
}

@Test func lastHasNoNext() {
    #expect(NextTrackPlanner.next(after: tracks[2].id, in: tracks) == nil)
}

@Test func missingIdHasNoNext() {
    #expect(NextTrackPlanner.next(after: TrackID(), in: tracks) == nil)
    #expect(NextTrackPlanner.next(after: TrackID(), in: [Track]()) == nil)
}
