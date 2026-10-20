import Foundation
import GRDB
import Testing
import WineupCore
@testable import WineupLibrary

private let ten = Array(repeating: 1.0, count: 10)
private func preset(_ name: String) -> EqPreset { EqPreset.validated(name: name, preamp: -2, bands: ten)! }

@Test func savedPresetSurvivesReopen() async throws {
    try await withTempDir { dir in
        let path = dir.appendingPathComponent("library.sqlite").path
        try EqPresetStore(db: LibraryDatabase(path: path)).save(preset("Meu"))
        let store = EqPresetStore(db: try LibraryDatabase(path: path))
        #expect(try store.userPresets() == [preset("Meu")])
        #expect(try store.allPresets().count == EqPreset.builtIns.count + 1)
    }
}

@Test func renameAndDeletePersist() async throws {
    try await withTempDir { dir in
        let path = dir.appendingPathComponent("library.sqlite").path
        let store = EqPresetStore(db: try LibraryDatabase(path: path))
        try store.save(preset("A"))
        try store.save(preset("B"))
        try store.rename(from: "A", to: "C")
        try store.delete(name: "B")
        let again = EqPresetStore(db: try LibraryDatabase(path: path))
        #expect(try again.userPresets().map(\.name) == ["C"])
        #expect(throws: EqPresetStoreError.self) { try again.delete(name: "Nada") }
    }
}

@Test func reservedAndDuplicateNamesThrow() async throws {
    try await withTempDir { dir in
        let store = EqPresetStore(db: try makeTempDatabase(in: dir))
        #expect(throws: EqPresetStoreError.self) { try store.save(preset("Flat")) }
        try store.save(preset("A"))
        try store.save(preset("B"))
        #expect(throws: EqPresetStoreError.self) { try store.rename(from: "A", to: "B") }
        #expect(throws: EqPresetStoreError.self) { try store.rename(from: "A", to: "Vocal") }
    }
}

@Test func corruptJSONFallsBackToBuiltIns() async throws {
    try await withTempDir { dir in
        let db = try makeTempDatabase(in: dir)
        try await db.pool.write {
            try $0.execute(sql: "INSERT INTO app_setting (key, value) VALUES ('eq.presets.v1', '{lixo')")
        }
        let store = EqPresetStore(db: db)
        #expect(try store.userPresets().isEmpty)
        #expect(try store.allPresets() == EqPreset.builtIns)
    }
}

@Test func outOfRangePresetsAreDropped() async throws {
    try await withTempDir { dir in
        let db = try makeTempDatabase(in: dir)
        let json = #"[{"name":"Ruim","preamp":0,"bands":[99,0,0,0,0,0,0,0,0,0]},{"name":"Bom","preamp":0,"bands":[0,0,0,0,0,0,0,0,0,0]}]"#
        try await db.pool.write {
            try $0.execute(sql: "INSERT INTO app_setting (key, value) VALUES ('eq.presets.v1', ?)", arguments: [json])
        }
        #expect(try EqPresetStore(db: db).userPresets().map(\.name) == ["Bom"])
    }
}

@Test func currentStatePersists() async throws {
    try await withTempDir { dir in
        let path = dir.appendingPathComponent("library.sqlite").path
        let state = EqState(preamp: -3, bands: ten, bypass: true, presetName: "Vocal")
        EqPresetStore(db: try LibraryDatabase(path: path)).saveCurrent(state)
        #expect(EqPresetStore(db: try LibraryDatabase(path: path)).loadCurrent() == state)
    }
}
