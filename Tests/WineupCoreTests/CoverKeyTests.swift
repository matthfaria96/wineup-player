import XCTest
@testable import WineupCore

final class CoverKeyTests: XCTestCase {
    func testSameAlbumSameFolderShareKey() {
        let a = CoverKey.album(for: URL(fileURLWithPath: "/m/Band/Album/01.flac"), album: "Album")
        let b = CoverKey.album(for: URL(fileURLWithPath: "/m/Band/Album/15.flac"), album: " album ")
        XCTAssertNotNil(a)
        XCTAssertEqual(a, b)
    }

    func testDifferentFolderOrAlbumDiffer() {
        let base = CoverKey.album(folderPath: "/m/A", album: "X")
        XCTAssertNotEqual(base, CoverKey.album(folderPath: "/m/B", album: "X"))
        XCTAssertNotEqual(base, CoverKey.album(folderPath: "/m/A", album: "Y"))
    }

    func testMissingAlbumHasNoKey() {
        XCTAssertNil(CoverKey.album(folderPath: "/m/A", album: nil))
        XCTAssertNil(CoverKey.album(folderPath: "/m/A", album: "   "))
    }

    func testFolderKeyIgnoresTrailingSlashAndDots() {
        XCTAssertEqual(CoverKey.folder("/m/A/"), CoverKey.folder("/m/B/../A"))
        XCTAssertNotEqual(CoverKey.folder("/m/A"), CoverKey.album(folderPath: "/m/A", album: "A"))
    }
}
