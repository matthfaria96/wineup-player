import Foundation
import Testing
@testable import WineupCore

@Suite("Letra: ajuste de tempo")
struct LyricsTimingTests {
    @Test func shiftMovesEveryTimestampAndKeepsTheRest() {
        let lrc = "[ar:Banda]\n[00:01.00]Primeira\n[00:10.50][01:02.00]Refrão\nsem marca\n[00:00.10]Começo"
        let shifted = LyricsTiming.shift(lrc, by: 0.25)
        #expect(shifted == "[ar:Banda]\n[00:01.25]Primeira\n[00:10.75][01:02.25]Refrão\nsem marca\n[00:00.35]Começo")
        let back = LyricsTiming.shift(lrc, by: -0.25)
        #expect(back.contains("[00:00.00]Começo"))       // nunca negativo
        #expect(back.contains("[01:01.75]Refrão"))
    }

    @Test func formatRoundsToCentiseconds() {
        #expect(LyricsTiming.format(62.255) == "01:02.26")
        #expect(LyricsTiming.format(0) == "00:00.00")
    }
}
