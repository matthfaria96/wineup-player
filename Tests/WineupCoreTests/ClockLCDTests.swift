import Testing
@testable import WineupCore

struct ClockLCDTests {
    @Test func formatsByLength() {
        #expect(Clock.lcd(233, negative: true) == "-03:53")
        #expect(Clock.lcd(59 * 60 + 59) == "59:59")
        #expect(Clock.lcd(3600) == "1:00:00")
        #expect(Clock.lcd(9 * 3600 + 59 * 60 + 59, negative: true) == "-9:59:59")
        #expect(Clock.lcd(10 * 3600) == "10:00:00")
        #expect(Clock.lcd(1_000_000) == "99:59:59")
        #expect(Clock.lcd(-5) == "00:00")
    }
}
