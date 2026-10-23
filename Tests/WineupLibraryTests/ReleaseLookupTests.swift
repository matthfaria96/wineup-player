import Foundation
import Testing
@testable import WineupLibrary

private let releaseJSON = """
{"id":"okc","title":"OK Computer","date":"1997-05-21","artist-credit":[{"name":"Radiohead"}],
 "release-group":{"id":"rg","primary-type":"Album","genres":[{"name":"alternative rock","count":9}]},
 "label-info":[{"catalog-number":"NODATA 02","label":{"name":"Parlophone"}}],
 "media":[{"position":1,"format":"CD","tracks":[
   {"position":1,"number":"1","title":"Airbag","length":284000,"recording":{"id":"r1"}},
   {"position":2,"number":"2","title":"Paranoid Android","length":383000,"recording":{"id":"r2"}},
   {"position":6,"number":"6","title":"Karma Police","length":264000,"recording":{"id":"r6"}}]}]}
"""

@Suite("Busca por álbum")
struct ReleaseLookupTests {
    @Test func searchSummaryColumns() async throws {
        let json = """
        {"releases":[{"id":"a","score":100,"title":"OK Computer","date":"1997-06-16","country":"GB","track-count":12,
          "artist-credit":[{"name":"Radiohead"}],"release-group":{"id":"rg","primary-type":"Album"},
          "label-info":[{"catalog-number":"7243","label":{"name":"Parlophone"}}],"media":[{"format":"CD","track-count":12}]}]}
        """
        let mb = MusicBrainzClient(fetcher: StubFetcher([("ws/2/release/", 200, json)]), minimumInterval: 0)
        let r = try #require(try await mb.searchReleases(artist: "Radiohead", album: "OK Computer").first)
        #expect(r.year == "1997" && r.trackCount == 12 && r.type == "Album")
        #expect(r.label == "Parlophone" && r.catalogNumber == "7243" && r.format == "CD" && r.country == "GB")
    }

    @Test func detailParsesTracksAndGenre() throws {
        let obj = try JSONSerialization.jsonObject(with: Data(releaseJSON.utf8)) as! [String: Any]
        let d = try #require(MusicBrainzClient.detail(obj))
        #expect(d.tracks.count == 3 && d.tracks[2].number == 6 && d.tracks[2].duration == 264)
        #expect(d.tracks[2].artist == "Radiohead" && d.genre == "Alternative rock" && d.label == "Parlophone")
        #expect(d.albumFields["year"] == "1997")
    }

    @Test func matcherUsesTitleDurationAndNumber() throws {
        let obj = try JSONSerialization.jsonObject(with: Data(releaseJSON.utf8)) as! [String: Any]
        let d = try #require(MusicBrainzClient.detail(obj))
        let files = [
            FixerFile(url: URL(fileURLWithPath: "/m/06 - Karma Police (Remastered).flac"), duration: 263),
            FixerFile(url: URL(fileURLWithPath: "/m/x.flac"), fields: ["title": "Airbag"], duration: 284),
            FixerFile(url: URL(fileURLWithPath: "/m/Outra Música.flac"), duration: 100)]
        let m = TrackMatcher.match(files: files, release: d)
        #expect(m[files[0].id] == 2 && m[files[1].id] == 0 && m[files[2].id] == nil)
    }
}

@Suite("Procurar capas")
struct CoverSearchTests {
    @Test func iTunesArtworkGoesTo1000px() {
        let list = CoverSearch.iTunesAlbums([["collectionId": 1, "collectionName": "OK Computer", "artistName": "Radiohead",
            "releaseDate": "1997-05-21T07:00:00Z", "trackCount": 12,
            "artworkUrl100": "https://is1.mzstatic.com/x/100x100bb.jpg"]])
        #expect(list.first?.fullURL.absoluteString == "https://is1.mzstatic.com/x/1000x1000bb.jpg")
        #expect(list.first?.date == "1997-05-21" && list.first?.detail == "12 faixas")
    }
}
