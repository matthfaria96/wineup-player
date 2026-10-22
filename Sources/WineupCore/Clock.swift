import Foundation

public enum Clock {
    public static func format(_ seconds: Int) -> String {
        let total = max(seconds, 0)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, secs)
            : String(format: "%d:%02d", minutes, secs)
    }

    /// Visor LCD: "MM:SS" até 1 h, "H:MM:SS" até 10 h e "HH:MM:SS" acima (até 99:59:59).
    public static func lcd(_ seconds: Int, negative: Bool = false) -> String {
        let total = min(max(seconds, 0), 99 * 3600 + 59 * 60 + 59)
        let hours = total / 3600, minutes = (total % 3600) / 60, secs = total % 60
        let body: String
        switch hours {
        case 0: body = String(format: "%02d:%02d", minutes, secs)
        case 1..<10: body = String(format: "%d:%02d:%02d", hours, minutes, secs)
        default: body = String(format: "%02d:%02d:%02d", hours, minutes, secs)
        }
        return (negative ? "-" : "") + body
    }
}
