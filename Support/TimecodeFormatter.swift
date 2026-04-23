import Foundation

enum TimecodeFormatter {
    static func string(from seconds: TimeInterval) -> String {
        guard seconds.isFinite, !seconds.isNaN else {
            return "--:--"
        }

        let total = max(0, Int(seconds.rounded(.down)))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let remainder = total % 60

        if hours > 0 {
            return String(format: "%02d:%02d:%02d", hours, minutes, remainder)
        }

        return String(format: "%02d:%02d", minutes, remainder)
    }
}
