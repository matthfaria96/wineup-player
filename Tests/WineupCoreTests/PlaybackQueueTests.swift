import Foundation
import Testing
@testable import WineupCore

private func q(_ n: Int, at i: Int? = 0) -> PlaybackQueue<Int> {
    PlaybackQueue(items: Array(0..<n), currentIndex: i)
}

@Test func offEndsWithNil() {
    var queue = q(3)
    #expect(queue.nextIndex() == 1)
    queue = queue.advanced()!.advanced()!
    #expect(queue.current == 2)
    #expect(queue.nextIndex() == nil)
    #expect(queue.advanced() == nil)
}

@Test func allWrapsAround() {
    let queue = q(3, at: 2).withRepeat(.all)
    #expect(queue.nextIndex() == 0)
    #expect(q(3, at: 0).withRepeat(.all).previousIndex() == 2)
}

@Test func oneRepeatsSame() {
    let queue = q(3, at: 1).withRepeat(.one)
    #expect(queue.nextIndex() == 1)
    #expect(queue.previousIndex() == 1)
}

@Test func movingKeepsCurrentItem() {
    let queue = q(5, at: 1)
    let moved = queue.moving(from: IndexSet(integer: 3), to: 0)
    #expect(moved.items == [3, 0, 1, 2, 4])
    #expect(moved.current == 1)
    let movedCurrent = queue.moving(from: IndexSet(integer: 1), to: 4)
    #expect(movedCurrent.items == [0, 2, 3, 1, 4])
    #expect(movedCurrent.current == 1)
}

@Test func removingCurrent() {
    let queue = q(3, at: 1).removing(at: 1)
    #expect(queue.items == [0, 2])
    #expect(queue.current == 2)
    let last = q(3, at: 2).removing(at: 2)
    #expect(last.current == nil)
    #expect(q(3, at: 2).removing(at: 0).current == 2)
}

@Test func shuffleDeterministicAndComplete() {
    let a = q(20, at: 5).shuffled(seed: 42)
    let b = q(20, at: 5).shuffled(seed: 42)
    #expect(a.shuffleOrder == b.shuffleOrder)
    #expect(a.shuffleOrder.first == 5)
    #expect(a.shuffleOrder.sorted() == Array(0..<20))
}

@Test func unshuffleKeepsCurrentAndOrder() {
    let s = q(10, at: 4).shuffled(seed: 7).advanced()!
    let u = s.unshuffled()
    #expect(u.items == Array(0..<10))
    #expect(u.current == s.current)
    #expect(u.shuffleOrder.isEmpty)
}

@Test func shuffledTraversalVisitsAll() {
    var queue = q(6, at: 0).shuffled(seed: 3)
    var seen = [queue.current!]
    while let n = queue.advanced() { queue = n; seen.append(queue.current!) }
    #expect(seen.sorted() == Array(0..<6))
}
