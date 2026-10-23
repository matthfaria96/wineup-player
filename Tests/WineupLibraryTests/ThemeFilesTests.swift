import Foundation
import Testing
@testable import WineupLibrary

@Suite("Temas: arquivos .wineuptheme")
struct ThemeFilesTests {
    private func store() throws -> (ThemeStore, URL) {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        return (ThemeStore(folder: dir), dir)
    }

    @Test func builtInsAreEditableAndRestorable() throws {
        let (s, dir) = try store()
        defer { try? FileManager.default.removeItem(at: dir) }
        #expect(s.files.map(\.id) == ["graphite", "wine", "green"])
        var edited = try #require(s.file("wine"))
        edited.colors["accent"] = "#00FF00"
        try s.save(edited)
        #expect(s.file("wine")?.colors["accent"] == "#00FF00" && s.isModifiedBuiltIn("wine"))
        try s.delete("wine")
        #expect(s.file("wine") == ThemeFile.wine && !s.isModifiedBuiltIn("wine"))
    }

    @Test func duplicateImportExportRoundTrip() throws {
        let (s, dir) = try store()
        defer { try? FileManager.default.removeItem(at: dir) }
        let mine = try s.duplicate(.graphite, name: "Meu Céu")
        #expect(mine.id == "meu-ceu" && s.files.contains(mine))
        let outside = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: outside) }
        let exported = outside.appendingPathComponent("x.wineuptheme")
        try s.export(mine, to: exported)
        let again = try s.importTheme(from: exported)
        #expect(again.id != mine.id && again.name == "Meu Céu" && s.files.count == 5)
        let text = try String(contentsOf: exported, encoding: .utf8)
        #expect(text.contains("\"format\" : \"wineup-theme\"") && text.contains("\"windowTop\""))
    }

    @Test func rejectsForeignJSON() throws {
        let (s, dir) = try store()
        defer { try? FileManager.default.removeItem(at: dir) }
        let bad = dir.appendingPathComponent("bad.json")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data(#"{"format":"outra","version":1,"id":"x","name":"X","author":"","colors":{}}"#.utf8).write(to: bad)
        #expect(throws: (any Error).self) { try s.importTheme(from: bad) }
    }
}
