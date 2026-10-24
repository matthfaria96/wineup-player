import Foundation
import Testing
@testable import WineupAudio
import WineupCore

@Suite("Avanço gapless da fila")
struct GaplessAdvanceTests {
    private let urls = (0..<3).map { URL(fileURLWithPath: "/tmp/faixa\($0).flac") }

    private func queue(_ repeatMode: RepeatMode, at index: Int = 0) -> PlaybackQueue<URL> {
        PlaybackQueue(items: urls, currentIndex: index).withRepeat(repeatMode)
    }

    @Test func advancesToQueuedNext() {
        #expect(GaplessAdvance.index(in: queue(.off), started: urls[1], fromQueue: true) { $0 } == 1)
    }

    /// Repetir uma: a mesma faixa recomeça e precisa ser reenfileirada (antes tocava só duas vezes).
    @Test func repeatOneRestartsEveryTime() {
        var q = queue(.one, at: 2)
        for _ in 0..<5 {
            let index = GaplessAdvance.index(in: q, started: urls[2], fromQueue: true) { $0 }
            #expect(index == 2)
            q = q.selecting(index: index!)
        }
    }

    @Test func startFromPlayIsNotAnAdvance() {
        #expect(GaplessAdvance.index(in: queue(.one), started: urls[0], fromQueue: false) { $0 } == nil)
    }

    @Test func unexpectedURLIsIgnored() {
        #expect(GaplessAdvance.index(in: queue(.off), started: urls[2], fromQueue: true) { $0 } == nil)
        #expect(GaplessAdvance.index(in: queue(.off, at: 2), started: urls[0], fromQueue: true) { $0 } == nil)
    }

    @Test func repeatAllWrapsToFirst() {
        #expect(GaplessAdvance.index(in: queue(.all, at: 2), started: urls[0], fromQueue: true) { $0 } == 0)
    }
}
