import SwiftUI
import WineupCore

extension MarkColor {
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
