import Foundation

extension TimeInterval {
    /// Formats as "M:SS" or "H:MM:SS" when hours > 0.
    var formattedAsTimestamp: String {
        let totalSeconds = Int(max(0, self))
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }
}
