import Foundation
import GRDB
import WineupCore

public struct EqState: Codable, Sendable, Equatable {
    public var preamp: Double
    public var bands: [Double]
    public var bypass: Bool
    public var presetName: String?

    public init(preamp: Double, bands: [Double], bypass: Bool, presetName: String? = nil) {
        self.preamp = preamp
        self.bands = bands
        self.bypass = bypass
        self.presetName = presetName
    }
}

public enum EqPresetStoreError: Error, Sendable {
    case duplicateName, reservedName, invalid, notFound
}

/// Presets do usuário e estado atual do EQ em `app_setting` (JSON versionado).
public struct EqPresetStore: Sendable {
    static let presetsKey = "eq.presets.v1"
    static let currentKey = "eq.current.v1"
    static let maxPresets = 200

    private let db: LibraryDatabase

    public init(db: LibraryDatabase) { self.db = db }

    public func userPresets() throws -> [EqPreset] {
        guard let raw = try readValue(Self.presetsKey), let data = raw.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([EqPreset].self, from: data) else { return [] }
        var seen = Set<String>()
        var out: [EqPreset] = []
        for p in decoded {
            guard let v = EqPreset.validated(name: p.name, preamp: p.preamp, bands: p.bands),
                  !EqPreset.isBuiltInName(v.name),
                  seen.insert(v.name.lowercased()).inserted else { continue }
            out.append(v)
            if out.count >= Self.maxPresets { break }
        }
        return out
    }

    public func allPresets() throws -> [EqPreset] {
        EqPreset.builtIns + (try userPresets())
    }

    public func save(_ preset: EqPreset) throws {
        guard let valid = EqPreset.validated(name: preset.name, preamp: preset.preamp, bands: preset.bands) else {
            throw EqPresetStoreError.invalid
        }
        if EqPreset.isBuiltInName(valid.name) { throw EqPresetStoreError.reservedName }
        var list = try userPresets()
        if let i = list.firstIndex(where: { $0.name.lowercased() == valid.name.lowercased() }) {
            list[i] = valid
        } else {
            guard list.count < Self.maxPresets else { throw EqPresetStoreError.invalid }
            list.append(valid)
        }
        try writeUserPresets(list)
    }

    public func rename(from old: String, to new: String) throws {
        var list = try userPresets()
        guard let i = list.firstIndex(where: { $0.name == old }) else { throw EqPresetStoreError.notFound }
        guard let renamed = EqPreset.validated(name: new, preamp: list[i].preamp, bands: list[i].bands) else {
            throw EqPresetStoreError.invalid
        }
        if EqPreset.isBuiltInName(renamed.name) { throw EqPresetStoreError.reservedName }
        if list.enumerated().contains(where: { $0.offset != i && $0.element.name.lowercased() == renamed.name.lowercased() }) {
            throw EqPresetStoreError.duplicateName
        }
        list[i] = renamed
        try writeUserPresets(list)
    }

    public func delete(name: String) throws {
        let list = try userPresets()
        guard list.contains(where: { $0.name == name }) else { throw EqPresetStoreError.notFound }
        try writeUserPresets(list.filter { $0.name != name })
    }

    public func loadCurrent() -> EqState? {
        guard let raw = try? readValue(Self.currentKey), let data = raw.data(using: .utf8),
              let s = try? JSONDecoder().decode(EqState.self, from: data),
              EqPreset.validated(name: "x", preamp: s.preamp, bands: s.bands) != nil else { return nil }
        return s
    }

    public func saveCurrent(_ state: EqState) {
        guard EqPreset.validated(name: "x", preamp: state.preamp, bands: state.bands) != nil,
              let data = try? JSONEncoder().encode(state), let text = String(data: data, encoding: .utf8) else { return }
        try? writeValue(Self.currentKey, text)
    }

    // MARK: - app_setting

    private func writeUserPresets(_ list: [EqPreset]) throws {
        let data = try JSONEncoder().encode(list)
        try writeValue(Self.presetsKey, String(decoding: data, as: UTF8.self))
    }

    private func readValue(_ key: String) throws -> String? {
        try db.pool.read { database in
            try String.fetchOne(database, sql: "SELECT value FROM app_setting WHERE key = ?", arguments: [key])
        }
    }

    private func writeValue(_ key: String, _ value: String) throws {
        try db.pool.write { database in
            try database.execute(
                sql: "INSERT INTO app_setting (key, value) VALUES (?, ?) ON CONFLICT(key) DO UPDATE SET value = excluded.value",
                arguments: [key, value])
        }
    }
}
