import Foundation
import Testing
import WineupCore
@testable import WineupLibrary

struct LibraryBootstrapTests {
    private func makeMusic(_ dir: URL, files: Bool) throws -> URL {
        let music = dir.appendingPathComponent("Music", isDirectory: true)
        try FileManager.default.createDirectory(at: music, withIntermediateDirectories: true)
        if files { try Data("x".utf8).write(to: music.appendingPathComponent("a.wav")) }
        return music
    }

    @Test func firstRunAddsMusicDirectory() async throws {
        try await withTempDir { dir in
            let db = try makeTempDatabase(in: dir)
            let music = try makeMusic(dir, files: true)
            let root = try LibraryBootstrap.ensureDefaultRoot(database: db, musicDirectory: music)
            #expect(root != nil)
            let roots = try LibraryRootStore(db: db).roots()
            #expect(roots.count == 1)
            #expect(roots[0].url.path == music.resolvingSymlinksInPath().path)
        }
    }

    @Test func missingDirectoryIsHarmless() async throws {
        try await withTempDir { dir in
            let db = try makeTempDatabase(in: dir)
            let missing = dir.appendingPathComponent("Nope", isDirectory: true)
            #expect(try LibraryBootstrap.ensureDefaultRoot(database: db, musicDirectory: missing) == nil)
            #expect(try LibraryBootstrap.ensureDefaultRoot(database: db, musicDirectory: nil) == nil)
            #expect(try LibraryRootStore(db: db).roots().isEmpty)
        }
    }

    @Test func emptyDirectoryIsAdded() async throws {
        try await withTempDir { dir in
            let db = try makeTempDatabase(in: dir)
            let music = try makeMusic(dir, files: false)
            #expect(try LibraryBootstrap.ensureDefaultRoot(database: db, musicDirectory: music) != nil)
        }
    }

    @Test func secondRunDoesNotReAdd() async throws {
        try await withTempDir { dir in
            let db = try makeTempDatabase(in: dir)
            let music = try makeMusic(dir, files: true)
            let root = try #require(try LibraryBootstrap.ensureDefaultRoot(database: db, musicDirectory: music))
            try LibraryRootStore(db: db).removeRoot(id: root.id)
            #expect(try LibraryBootstrap.ensureDefaultRoot(database: db, musicDirectory: music) == nil)
            #expect(try LibraryRootStore(db: db).roots().isEmpty)
        }
    }

    @Test func existingUserRootBlocksDefault() async throws {
        try await withTempDir { dir in
            let db = try makeTempDatabase(in: dir)
            let music = try makeMusic(dir, files: true)
            let other = dir.appendingPathComponent("Other", isDirectory: true)
            try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)
            try LibraryRootStore(db: db).addRoot(other)
            #expect(try LibraryBootstrap.ensureDefaultRoot(database: db, musicDirectory: music) == nil)
            #expect(try LibraryRootStore(db: db).roots().count == 1)
        }
    }
}
