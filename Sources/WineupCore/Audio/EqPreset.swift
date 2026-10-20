import Foundation

public struct EqPreset: Codable, Sendable, Equatable, Identifiable {
    public var id: String { name }
    public let name: String
    public let preamp: Double
    public let bands: [Double]

    public static let bandCount = 10
    public static let maxNameLength = 64

    /// Valida (dados vêm do banco ou do usuário): nome trimado 1...64, 10 bandas finitas em +/-12, preamp em +/-24.
    public static func validated(name: String, preamp: Double, bands: [Double]) -> EqPreset? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= maxNameLength else { return nil }
        guard preamp.isFinite, abs(preamp) <= 24 else { return nil }
        guard bands.count == bandCount, bands.allSatisfy({ $0.isFinite && abs($0) <= 12 }) else { return nil }
        return EqPreset(name: trimmed, preamp: preamp, bands: bands)
    }

    public static let builtIns: [EqPreset] = [
        EqPreset(name: "Flat", preamp: 0, bands: Array(repeating: 0, count: 10)),
        EqPreset(name: "Vintage", preamp: 0, bands: [6, -2, -4, -3, -2, 0, -3, -2, 4, 5]),
        EqPreset(name: "Bass Boost", preamp: 0, bands: [8, 6, 4, 2, 0, 0, 0, 0, 0, 0]),
        EqPreset(name: "Vocal", preamp: 0, bands: [-3, -2, 0, 3, 5, 5, 3, 1, -1, -2]),
    ]

    public static func isBuiltInName(_ name: String) -> Bool {
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return builtIns.contains { $0.name.lowercased() == n }
    }
}
