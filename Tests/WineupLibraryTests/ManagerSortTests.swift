import Foundation
import Testing
@testable import WineupLibrary

@Suite("Ordenação do gerenciador de metadados")
struct ManagerSortTests {
    private func sorted(_ values: [String]) -> [String] {
        values.sorted { NaturalSortKey.make($0) < NaturalSortKey.make($1) }
    }

    @Test func numbersCompareByValue() {
        #expect(sorted(["Faixa 10", "Faixa 2", "Faixa 1"]) == ["Faixa 1", "Faixa 2", "Faixa 10"])
        #expect(sorted(["10 b.flac", "9 a.flac"]) == ["9 a.flac", "10 b.flac"])
    }

    @Test func ignoresCaseAndAccents() {
        #expect(NaturalSortKey.make("Álbum") == NaturalSortKey.make("album"))
        #expect(sorted(["Zeca", "Ábaco", "beto"]) == ["Ábaco", "beto", "Zeca"])
    }

    @Test func sameOrderAsLocalizedStandardForCommonNames() {
        let names = ["Faixa 3", "faixa 12", "Água", "Banda", "Ópera 2", "Ópera 10", "zebra", "01 Intro"]
        let expected = names.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        #expect(sorted(names) == expected)
    }

    @Test func sortValueReadsCommonTypes() {
        #expect(SortValue(any: "a") == .text("a"))
        #expect(SortValue(any: 3) == .number(3))
        #expect(SortValue(any: Int64(7)) == .number(7))
        #expect(SortValue(any: 1.5) == .number(1.5))
        #expect(SortValue(any: [1]) == .number(0))
    }

    @Test func orderUsesEachCriterionAndKeepsTiesStable() {
        let keys: [[SortValue]] = [[.text("b"), .number(2)], [.text("a"), .number(5)], [.text("b"), .number(1)], [.text("a"), .number(5)]]
        #expect(ManagerSort.order(keys, ascending: [true, true]) == [1, 3, 2, 0])
        #expect(ManagerSort.order(keys, ascending: [false, true]) == [2, 0, 1, 3])
        #expect(ManagerSort.order(keys, ascending: []) == [0, 1, 2, 3])
    }
}
