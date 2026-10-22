import Testing
@testable import WineupCore

struct StableTrackIDTests {
    @Test func samePathSameID() {
        #expect(TrackID(stableKey: "/Music/a.flac") == TrackID(stableKey: "/Music/a.flac"))
        #expect(TrackID(stableKey: "/Music/a.flac") != TrackID(stableKey: "/Music/b.flac"))
        #expect(TrackID(stableKey: "") == TrackID(stableKey: ""))
    }
}
