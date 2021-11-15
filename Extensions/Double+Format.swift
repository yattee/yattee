import Foundation

extension Double {
    func formattedAsPlaybackTime() -> String? {
        guard !isZero else {
            return nil
        }

        let formatter = DateComponentsFormatter()

        formatter.unitsStyle = .positional
        formatter.allowedUnits = self >= (60 * 60) ? [.hour, .minute, .second] : [.minute, .second]
        formatter.zeroFormattingBehavior = [.pad]

        return formatter.string(from: self)
    }

    func formattedAsRelativeTime() -> String? {
        let date = Date(timeIntervalSince1970: self)

        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full

        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
