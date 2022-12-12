import Cache
import Foundation
import SwiftyJSON

protocol CacheModel {
    var storage: Storage<String, JSON>? { get }

    func clear()
}

extension CacheModel {
    func clear() {
        try? storage?.removeAll()
    }

    func getFormattedDate(_ date: Date?) -> String {
        guard let date else { return "unknown" }

        let isSameDay = Calendar(identifier: .iso8601).isDate(date, inSameDayAs: Date())
        let formatter = isSameDay ? dateFormatterForTimeOnly : dateFormatter
        return formatter.string(from: date)
    }

    var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .medium

        return formatter
    }

    var dateFormatterForTimeOnly: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .medium

        return formatter
    }

    var iso8601DateFormatter: ISO8601DateFormatter { .init() }
}
