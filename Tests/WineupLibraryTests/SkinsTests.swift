import Foundation
import Testing
@testable import WineupLibrary

@Suite("Skins .wineupskin")
struct SkinsTests {
    /// Pasta Resources/Skins do repositório (o skin de verdade que vai no app).
    static let builtIns = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().appendingPathComponent("Resources/Skins")

    private func store() -> (SkinStore, URL) {
        let user = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        return (SkinStore(builtInFolder: Self.builtIns, userFolder: user), user)
    }

    @Test func starryNightIsCompleteAndAllFilesExist() throws {
        let (s, user) = store()
        defer { try? FileManager.default.removeItem(at: user) }
        let skin = try #require(s.skin(SkinStore.defaultID))
        #expect(skin.builtIn && skin.name == "Noite Estrelada")
        for file in skin.manifest.referencedFiles {
            #expect(FileManager.default.fileExists(atPath: skin.file(file).path), "falta \(file)")
        }
        let window = skin.manifest.window
        #expect(window.layers.map(\.kind) == [.flow, .swirl, .glow, .stars])
        #expect(window.layers.last?.points.count == 11)
        #expect(skin.manifest.panelStyle("player")?.frame?.image == "frame.png")
        #expect(skin.manifest.credits.first?.license == "Domínio público")
    }

    @Test func minimalManifestUsesDefaults() throws {
        let m = try SkinStore.decode(Data(#"{"format":"wineup-skin","id":"x","name":"X","window":{"layers":[{"kind":"stars"}]}}"#.utf8))
        #expect(m.version == 1 && m.colors.isEmpty && m.window.layers.first?.intensity == 0.7)
        #expect(throws: (any Error).self) { try SkinStore.decode(Data(#"{"format":"outro","id":"x","name":"X"}"#.utf8)) }
    }

    @Test func editRestoreDuplicateExportImport() throws {
        let (s, user) = store()
        defer { try? FileManager.default.removeItem(at: user) }
        var m = try #require(s.skin(SkinStore.defaultID)).manifest
        m.colors["accent"] = "#00FF00"
        try s.save(m)
        #expect(s.skin(m.id)?.manifest.colors["accent"] == "#00FF00" && !s.skin(m.id)!.builtIn && s.isModifiedBuiltIn(m.id))
        try s.delete(m.id)
        #expect(s.skin(m.id)?.builtIn == true && !s.isModifiedBuiltIn(m.id))

        let copy = try s.duplicate(m.id, name: "Minha Noite")
        #expect(copy.id == "minha-noite" && FileManager.default.fileExists(atPath: copy.file("frame.png").path))
        let zip = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).wineupskin")
        defer { try? FileManager.default.removeItem(at: zip) }
        try s.export(copy.id, to: zip)
        let imported = try s.importSkin(from: zip)
        #expect(imported.id != copy.id && imported.name == "Minha Noite")
        #expect(FileManager.default.fileExists(atPath: imported.file("background.jpg").path))
    }

    @Test func rejectsPathsOutsideTheSkin() throws {
        let (s, user) = store()
        defer { try? FileManager.default.removeItem(at: user) }
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let pkg = dir.appendingPathComponent("mal")
        try FileManager.default.createDirectory(at: pkg, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        try Data(#"{"format":"wineup-skin","id":"mal","name":"Mal","window":{"background":{"image":"../../segredo.jpg"}}}"#.utf8)
            .write(to: pkg.appendingPathComponent("skin.json"))
        let zip = dir.appendingPathComponent("mal.wineupskin")
        try SkinStore.ditto(["-c", "-k", "--keepParent", pkg.path, zip.path])
        #expect(throws: (any Error).self) { try s.importSkin(from: zip) }
    }
}
