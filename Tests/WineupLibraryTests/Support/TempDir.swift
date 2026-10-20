import Foundation
@testable import WineupLibrary

func withTempDir<T>(_ body: (URL) async throws -> T) async throws -> T {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("WineupTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }
    return try await body(dir)
}

func makeTempDatabase(in dir: URL) throws -> LibraryDatabase {
    try LibraryDatabase(path: dir.appendingPathComponent("library.sqlite").path)
}
