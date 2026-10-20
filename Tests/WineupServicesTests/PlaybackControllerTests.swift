import Foundation
import Testing
import WineupCore
@testable import WineupServices

final class FakeEngine: AudioEngine, @unchecked Sendable {
    var played: [URL] = []
    var enqueued: [URL] = []
    var stopped = 0
    var currentTime: TimeInterval { 0 }
    var totalTime: TimeInterval { 0 }
    var isPlaying: Bool { false }
    func play(_ url: URL) throws { played.append(url) }
    func enqueue(_ url: URL) throws { enqueued.append(url) }
    func pause() {}
    func resume() {}
    func stop() { stopped += 1 }
    func seek(toFraction fraction: Double) {}
    func setVolume(_ volume: Double) {}
    func setRate(_ rate: Double) {}
    func setBalance(_ pan: Double) {}
    func setReplayGain(linear: Double) {}
    func applyEqualizer(preamp: Double, bands: [Double], bypass: Bool) {}
}

private func entries(_ n: Int) -> [QueueEntry] {
    (0..<n).map {
        QueueEntry(fileID: Int64($0), url: URL(fileURLWithPath: "/tmp/t\($0).mp3"),
                   title: "T\($0)", artist: "A", duration: 10)
    }
}

@MainActor
@Suite struct PlaybackControllerTests {
    @Test func replaceQueueAutoplayEnqueuesNext() {
        let engine = FakeEngine()
        let c = PlaybackController(engine: engine)
        let e = entries(3)
        c.replaceQueue(e, startAt: 0, autoplay: true)
        #expect(engine.played == [e[0].url])
        #expect(engine.enqueued.last == e[1].url)
    }

    @Test func nowPlayingChangedMovesCurrent() {
        let engine = FakeEngine()
        let c = PlaybackController(engine: engine)
        let e = entries(3)
        c.replaceQueue(e, startAt: 0, autoplay: true)
        c.handleNowPlayingChanged(url: e[1].url)
        #expect(c.queue.currentIndex == 1)
        #expect(engine.enqueued.last == e[2].url)
    }

    @Test func repeatOneEnqueuesSame() {
        let engine = FakeEngine()
        let c = PlaybackController(engine: engine)
        let e = entries(3)
        c.replaceQueue(e, startAt: 1, autoplay: true)
        c.setRepeat(.one)
        #expect(engine.enqueued.last == e[1].url)
    }

    @Test func repeatAllWrapsToFirst() {
        let engine = FakeEngine()
        let c = PlaybackController(engine: engine)
        let e = entries(3)
        c.setRepeat(.all)
        c.replaceQueue(e, startAt: 2, autoplay: true)
        #expect(engine.enqueued.last == e[0].url)
    }

    @Test func shuffleSeedDrivesEnqueue() {
        let engine = FakeEngine()
        let c = PlaybackController(engine: engine)
        let e = entries(10)
        c.replaceQueue(e, startAt: 0, autoplay: true)
        c.setShuffle(true, seed: 99)
        let expected = c.queue.shuffleOrder[1]
        #expect(engine.enqueued.last == e[expected].url)
    }

    @Test func removeAndMoveRedoEnqueue() {
        let engine = FakeEngine()
        let c = PlaybackController(engine: engine)
        let e = entries(4)
        c.replaceQueue(e, startAt: 0, autoplay: true)
        c.remove(at: 1)
        #expect(engine.enqueued.last == e[2].url)
        c.move(from: IndexSet(integer: 2), to: 1)
        #expect(engine.enqueued.last == e[3].url)
    }

    @Test func nextAndPreviousPlay() {
        let engine = FakeEngine()
        let c = PlaybackController(engine: engine)
        let e = entries(3)
        c.replaceQueue(e, startAt: 0, autoplay: true)
        c.next()
        #expect(engine.played.last == e[1].url)
        c.previous()
        #expect(engine.played.last == e[0].url)
    }
}
