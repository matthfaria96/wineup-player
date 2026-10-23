import CoreGraphics
import ImageIO
import Foundation
import Testing
@testable import WineupLibrary

@Suite("Skins .wineupskin")
struct SkinsTests {
    /// Pasta Resources/Skins do repositório (o skin de verdade que vai no app).
    static let builtIns = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().appendingPathComponent("Resources/Skins")

    private func store() -> (SkinStore, URL) {
        // Cada teste numa pasta própria (os ajustes dos oficiais ficam ao lado de Skins).
        let user = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("Skins")
        return (SkinStore(builtInFolder: Self.builtIns, userFolder: user), user)
    }

    @Test func everyBuiltInSkinIsCompleteAndReadable() throws {
        let (s, user) = store()
        defer { try? FileManager.default.removeItem(at: user.deletingLastPathComponent()) }
        #expect(s.skins.map(\.id) == ["neon-gotico", "noite-estrelada", "pixelart-8bit"])
        for skin in s.skins {
            #expect(skin.builtIn)
            for file in skin.manifest.referencedFiles {
                #expect(FileManager.default.fileExists(atPath: skin.file(file).path), "falta \(file) em \(skin.id)")
            }
            #expect(SkinLegibility.issues(skin.manifest, folder: skin.folder).isEmpty, "texto ilegível em \(skin.id)")
            #expect(!skin.manifest.credits.isEmpty && !skin.manifest.description.isEmpty)
            // Mesmo padrão em todos os oficiais: arte, moldura, botões, campo, puxador, fontes e animações.
            let m = skin.manifest
            #expect(m.artwork != nil && m.window.background != nil && !m.window.layers.isEmpty, "\(skin.id)")
            #expect(m.controls.button != nil && m.controls.buttonOn != nil && m.controls.field != nil && m.controls.knob != nil, "\(skin.id)")
            #expect(m.panelStyle("player")?.frame != nil && !m.fonts.isEmpty && m.titleFont != nil, "\(skin.id)")
        }
        let skin = try #require(s.skin(SkinStore.defaultID))
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
        defer { try? FileManager.default.removeItem(at: user.deletingLastPathComponent()) }
        var m = try #require(s.skin(SkinStore.defaultID)).manifest
        m.colors["accent"] = "#00FF00"
        try s.save(m)
        #expect(s.skin(m.id)?.manifest.colors["accent"] == "#00FF00" && s.skin(m.id)!.builtIn && s.isModifiedBuiltIn(m.id))
        #expect(throws: (any Error).self) { try s.delete(m.id) }   // oficial não se apaga
        #expect(!FileManager.default.fileExists(atPath: user.appendingPathComponent(m.id).path))  // ajustes ficam em pasta separada
        try s.restoreOfficial(m.id)
        #expect(s.skin(m.id)?.manifest.colors["accent"] != "#00FF00" && !s.isModifiedBuiltIn(m.id))

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
        defer { try? FileManager.default.removeItem(at: user.deletingLastPathComponent()) }
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

@Suite("Skins: gerar a partir de imagem e legibilidade")
struct SkinGeneratorTests {
    private func photo(_ dir: URL, light: Bool) throws -> URL {
        let ctx = SkinGenerator.context(400, 300)
        let colors = light ? [CGColor(srgbRed: 0.95, green: 0.92, blue: 0.85, alpha: 1), CGColor(srgbRed: 1, green: 0.6, blue: 0.2, alpha: 1)]
                           : [CGColor(srgbRed: 0.05, green: 0.1, blue: 0.3, alpha: 1), CGColor(srgbRed: 0.9, green: 0.3, blue: 0.5, alpha: 1)]
        ctx.setFillColor(colors[0]); ctx.fill(CGRect(x: 0, y: 0, width: 400, height: 300))
        ctx.setFillColor(colors[1]); ctx.fillEllipse(in: CGRect(x: 150, y: 100, width: 100, height: 100))
        let url = dir.appendingPathComponent(light ? "claro.png" : "escuro.png")
        let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, ctx.makeImage()!, nil); CGImageDestinationFinalize(dest)
        return url
    }

    @Test(arguments: SkinGenerator.Style.allCases)
    func generatesCompleteReadableSkin(_ style: SkinGenerator.Style) throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = SkinStore(builtInFolder: nil, userFolder: dir.appendingPathComponent("Skins"))
        let skin = try store.createFromImage(try photo(dir, light: false), name: "Minha Foto", style: style)
        #expect(skin.id == "minha-foto" && !skin.builtIn)
        for f in skin.manifest.referencedFiles { #expect(FileManager.default.fileExists(atPath: skin.file(f).path), "falta \(f)") }
        let accent = try #require(SkinLegibility.rgb(skin.manifest.colors["accent"]))
        #expect(accent.r > 0.6 && accent.b > 0.3)   // rosa da imagem
        let onAccent = try #require(SkinLegibility.rgb(skin.manifest.colors["buttonTextOn"]))
        #expect(SkinGenerator.contrast(onAccent, accent) >= 4.5)
        #expect(SkinLegibility.issues(skin.manifest, folder: skin.folder).isEmpty)
    }

    @Test func lightImageIsDetectedAndFixed() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let img = try photo(dir, light: true)
        var m = SkinManifest(id: "x", name: "X")
        m.colors["text"] = "#FFFFFF"
        m.panels["default"] = .init(fill: .init(image: img.lastPathComponent, dim: 0))
        #expect(SkinLegibility.issues(m, folder: dir).count == 1)
        let fixed = SkinLegibility.autoFix(m, folder: dir)
        #expect(SkinLegibility.issues(fixed, folder: dir).isEmpty)
        #expect((fixed.panels["default"]?.fill?.dim ?? 0) < 0.92)
    }
}


@Suite("Skins: inspecionar antes de instalar")
struct SkinInspectTests {
    @Test func inspectDoesNotInstall() throws {
        let user = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent("Skins")
        let s = SkinStore(builtInFolder: SkinsTests.builtIns, userFolder: user)
        defer { try? FileManager.default.removeItem(at: user.deletingLastPathComponent()) }
        let zip = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).wineupskin")
        defer { try? FileManager.default.removeItem(at: zip) }
        try s.export(SkinStore.defaultID, to: zip)
        let preview = try s.inspect(zip)
        defer { try? FileManager.default.removeItem(at: preview.folder.deletingLastPathComponent()) }
        #expect(preview.name == "Noite Estrelada" && FileManager.default.fileExists(atPath: preview.file("frame.png").path))
        #expect(s.skins.count == 3 && s.isInstalled(preview.id))
    }
}

@Suite("Skins: oficiais protegidos")
struct OfficialSkinTests {
    @Test func oldEditsAreMovedOutOfUserFolder() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let user = root.appendingPathComponent("Skins")
        try FileManager.default.createDirectory(at: user, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: SkinsTests.builtIns.appendingPathComponent(SkinStore.defaultID),
                                         to: user.appendingPathComponent(SkinStore.defaultID))
        let s = SkinStore(builtInFolder: SkinsTests.builtIns, userFolder: user)
        #expect(!FileManager.default.fileExists(atPath: user.appendingPathComponent(SkinStore.defaultID).path))
        #expect(s.isModifiedBuiltIn(SkinStore.defaultID) && s.skin(SkinStore.defaultID)?.builtIn == true)
        let copy = try s.duplicate(SkinStore.defaultID, name: "Noite Estrelada")
        #expect(copy.id != SkinStore.defaultID && !copy.builtIn)
    }
}
