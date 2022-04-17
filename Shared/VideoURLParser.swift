import CoreMedia
import Foundation

struct VideoURLParser {
    let url: URL

    var id: String? {
        if urlComponents?.host == "youtu.be", let path = urlComponents?.path {
            return String(path.suffix(from: path.index(path.startIndex, offsetBy: 1)))
        }

        return queryItemValue("v")
    }

    var time: CMTime? {
        guard let time = queryItemValue("t") else {
            return nil
        }

        let timeComponents = parseTime(time)

        guard !timeComponents.isEmpty,
              let hours = TimeInterval(timeComponents["hours"] ?? "0"),
              let minutes = TimeInterval(timeComponents["minutes"] ?? "0"),
              let seconds = TimeInterval(timeComponents["seconds"] ?? "0")
        else {
            if let time = TimeInterval(time) {
                return .secondsInDefaultTimescale(time)
            }

            return nil
        }

        return .secondsInDefaultTimescale(seconds + (minutes * 60) + (hours * 60 * 60))
    }

    func queryItemValue(_ name: String) -> String? {
        queryItems.first { $0.name == name }?.value
    }

    private var queryItems: [URLQueryItem] {
        urlComponents?.queryItems ?? []
    }

    private var urlComponents: URLComponents? {
        URLComponents(url: url, resolvingAgainstBaseURL: false)
    }

    private func parseTime(_ time: String) -> [String: String] {
        let results = timeRegularExpression.matches(
            in: time,
            range: NSRange(time.startIndex..., in: time)
        )

        guard let match = results.first else {
            return [:]
        }

        var components: [String: String] = [:]

        for name in ["hours", "minutes", "seconds"] {
            let matchRange = match.range(withName: name)

            if let substringRange = Range(matchRange, in: time) {
                let capture = String(time[substringRange])
                components[name] = capture
            }
        }

        return components
    }

    private var timeRegularExpression: NSRegularExpression {
        try! NSRegularExpression(
            pattern: "(?:(?<hours>[0-9+])+h)?(?:(?<minutes>[0-9]+)m)?(?:(?<seconds>[0-9]*)s)?",
            options: .caseInsensitive
        )
    }
}
