import Testing
@testable import WineupCore

@Suite("Reproduzir tudo do artista")
struct ArtistQueueTests {
    private func t(_ title: String, _ album: String?, _ year: String?, _ d: Int = 200) -> Track {
        var x = Track(artist: "Banda", title: title, duration: d, mark: nil)
        x.album = album
        x.year = year
        return x
    }

    @Test func singleAndAlbumVersionPlayOnce() {
        let single = t("Hit", "Hit", "2019"), album = [t("Intro", "Disco", "2020"), t("Hit", "Disco", "2020", 201)]
        let out = ArtistQueue.make([single] + album, order: .byAlbum, dedupe: true)
        #expect(out.map(\.title) == ["Intro", "Hit"])
        #expect(out.last?.album == "Disco")
        #expect(ArtistQueue.make([single] + album, order: .byAlbum, dedupe: false).count == 3)
    }

    @Test func liveVersionWithDifferentLengthStays() {
        let out = ArtistQueue.make([t("Hit", "Disco", "2020", 200), t("Hit", "Ao Vivo", "2022", 260)], order: .byAlbum, dedupe: true)
        #expect(out.count == 2)
    }

    @Test func chronologicalKeepsAlbumTrackOrder() {
        let tracks = [t("B2", "Segundo", "2010"), t("B1", "Segundo", "2010"), t("A1", "Primeiro", "2005"), t("Z", nil, nil)]
        #expect(ArtistQueue.make(tracks, order: .chronological, dedupe: false).map(\.title) == ["A1", "B2", "B1", "Z"])
        #expect(ArtistQueue.make(tracks, order: .alphabetical, dedupe: false).map(\.title) == ["A1", "B1", "B2", "Z"])
    }
}
