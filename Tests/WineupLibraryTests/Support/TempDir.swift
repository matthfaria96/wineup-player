import Foundation
import GRDB
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

/// Registra uma execução da faixa (a tabela `play_event` segura a exclusão do arquivo).
func insertPlayEvent(_ db: Database, fileID: Int64) throws {
    try db.execute(sql: "INSERT INTO play_event (audio_file_id, played_at) VALUES (?, ?)", arguments: [fileID, Date()])
}
