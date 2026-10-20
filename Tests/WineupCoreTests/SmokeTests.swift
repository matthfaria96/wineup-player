import Foundation
import Testing
@testable import WineupCore

@Test func coreVersionIsSet() { #expect(WineupCore.version == "0.1.0") }

@Test func confidenceIsOrdered() { #expect(Confidence.low < .high) }

@Test func libraryRootContainsOnlyDescendants() {
    let root = LibraryRoot(url: URL(fileURLWithPath: "/Music"))
    #expect(root.contains(URL(fileURLWithPath: "/Music/a.flac")))
    #expect(!root.contains(URL(fileURLWithPath: "/Musica/a.flac")))
    #expect(!root.contains(URL(fileURLWithPath: "/Music/../Other/a.flac")))
}
