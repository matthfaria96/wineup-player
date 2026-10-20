import Testing
@testable import WineupCore

@Test func coreVersionIsSet() { #expect(WineupCore.version == "0.1.0") }
