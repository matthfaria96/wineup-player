import SwiftUI

enum MarkColor: String, CaseIterable, Identifiable {
    case green, blue, purple, red, orange, yellow

    var id: String { rawValue }

    var color: Color {
        switch self {
        case .green: Color(hex: 0x34C759)
        case .blue: Color(hex: 0x0A84FF)
        case .purple: Color(hex: 0xAF52DE)
        case .red: Color(hex: 0xFF453A)
        case .orange: Color(hex: 0xFF9F0A)
        case .yellow: Color(hex: 0xFFD60A)
        }
    }
}

struct Track: Identifiable, Hashable {
    let id: Int
    let artist: String
    let title: String
    let duration: Int
    let mark: MarkColor?
    var url: URL? = nil
    var album: String? = nil
    var year: String? = nil

    var displayName: String { "\(artist) - \(title)" }
}

enum Clock {
    static func format(_ seconds: Int) -> String {
        let total = max(seconds, 0)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, secs)
            : String(format: "%d:%02d", minutes, secs)
    }
}
