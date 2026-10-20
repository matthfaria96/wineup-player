import Foundation
import Testing
@testable import WineupCore

private let ten = Array(repeating: 0.0, count: 10)

@Test func validationRejectsBadInput() {
    #expect(EqPreset.validated(name: "  ", preamp: 0, bands: ten) == nil)
    #expect(EqPreset.validated(name: "x", preamp: 0, bands: [0, 0]) == nil)
    #expect(EqPreset.validated(name: "x", preamp: 0, bands: ten.enumerated().map { $0.offset == 0 ? 13 : 0 }) == nil)
    #expect(EqPreset.validated(name: "x", preamp: 0, bands: ten.enumerated().map { $0.offset == 0 ? .nan : 0 }) == nil)
    #expect(EqPreset.validated(name: "x", preamp: 25, bands: ten) == nil)
    #expect(EqPreset.validated(name: String(repeating: "a", count: 65), preamp: 0, bands: ten) == nil)
}

@Test func validationAcceptsAndTrims() {
    let p = EqPreset.validated(name: "  Meu  ", preamp: -3, bands: ten)
    #expect(p?.name == "Meu")
}

@Test func builtIns() {
    let names = EqPreset.builtIns.map(\.name)
    #expect(names == ["Flat", "Vintage", "Bass Boost", "Vocal"])
    #expect(EqPreset.builtIns[1].bands == [6, -2, -4, -3, -2, 0, -3, -2, 4, 5])
    #expect(EqPreset.builtIns.allSatisfy { EqPreset.validated(name: $0.name, preamp: $0.preamp, bands: $0.bands) == $0 })
}

@Test func codableRoundTrip() throws {
    let p = EqPreset.builtIns[2]
    let back = try JSONDecoder().decode(EqPreset.self, from: JSONEncoder().encode(p))
    #expect(back == p)
}
