import Foundation
import GRDB
import Testing
@testable import WineupLibrary

struct ScannerTests {
    @Test func tagReaderReadsWAV() async throws {
        try await withTempDir { dir in
            let url = dir.appendingPathComponent("a.wav")
            try WAVFixture.write(to: url)
            let tags = try TagReader.read(url)
            #expect((tags.duration ?? 0) > 0)
            #expect(tags.title == nil)
        }
    }

    @Test func tagReaderThrowsOnGarbage() async throws {
        try await withTempDir { dir in
            let url = dir.appendingPathComponent("bad.flac")
            try Data((0..<512).map { _ in UInt8.random(in: 0...255) }).write(to: url)
            #expect(throws: (any Error).self) { try TagReader.read(url) }
        }
    }

    @Test func enumeratorFiltersAndSkipsSymlinks() async throws {
        try await withTempDir { dir in
            let root = dir.appendingPathComponent("root", isDirectory: true)
            let outside = dir.appendingPathComponent("outside", isDirectory: true)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
            try WAVFixture.write(to: root.appendingPathComponent("a.wav"))
            try Data("x".utf8).write(to: root.appendingPathComponent("notes.txt"))
            try WAVFixture.write(to: root.appendingPathComponent(".wineup-hidden.wav"))
            try WAVFixture.write(to: outside.appendingPathComponent("b.wav"))
            try FileManager.default.createSymbolicLink(
                at: root.appendingPathComponent("link"), withDestinationURL: outside)
            try FileManager.default.createSymbolicLink(
                at: root.appendingPathComponent("c.wav"), withDestinationURL: outside.appendingPathComponent("b.wav"))
            let files = try FileEnumerator.enumerate(root: root, isCancelled: { false })
            #expect(files.count == 1)
            #expect(files.first?.path.hasSuffix("/a.wav") == true)
            #expect((files.first?.size ?? 0) > 0 && (files.first?.inode ?? 0) > 0)
        }
    }
}
