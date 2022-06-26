import CoreMedia
import Foundation

struct URLParser {
    static let prefixes: [Destination: [String]] = [
        .playlist: ["/playlist", "playlist"],
        .channel: ["/c", "c", "/channel", "channel"],
        .search: ["/results", "search"]
    ]

    enum Destination {
        case video, playlist, channel, search
        case favorites, subscriptions, popular, trending
    }

    var destination: Destination? {
        if hasAnyOfPrefixes(path, ["favorites"]) { return .favorites }
        if hasAnyOfPrefixes(path, ["subscriptions"]) { return .subscriptions }
        if hasAnyOfPrefixes(path, ["popular"]) { return .popular }
        if hasAnyOfPrefixes(path, ["trending"]) { return .trending }

        if hasAnyOfPrefixes(path, Self.prefixes[.playlist]!) || queryItemValue("v") == "playlist" {
            return .playlist
        } else if hasAnyOfPrefixes(path, Self.prefixes[.channel]!) {
            return .channel
        } else if hasAnyOfPrefixes(path, Self.prefixes[.search]!) {
            return .search
        }

        guard let id = videoID, !id.isEmpty else {
            return nil
        }

        return .video
    }

    var url: URL

    var videoID: String? {
        if host == "youtu.be", !path.isEmpty {
            return String(path.suffix(from: path.index(path.startIndex, offsetBy: 1)))
        }

        return queryItemValue("v")
    }

    var time: Int? {
        guard let time = queryItemValue("t") else {
            return nil
        }

        let timeComponents = parseTime(time)

        guard !timeComponents.isEmpty,
              let hours = Int(timeComponents["hours"] ?? "0"),
              let minutes = Int(timeComponents["minutes"] ?? "0"),
              let seconds = Int(timeComponents["seconds"] ?? "0")
        else {
            return Int(time)
        }

        return Int(seconds + (minutes * 60) + (hours * 60 * 60))
    }

    var playlistID: String? {
        guard destination == .playlist else { return nil }

        return queryItemValue("list")
    }

    var searchQuery: String? {
        guard destination == .search else { return nil }

        return queryItemValue("search_query")?.replacingOccurrences(of: "+", with: " ")
    }

    var channelName: String? {
        guard hasAnyOfPrefixes(path, ["c/", "/c/"]) else { return nil }
        return removePrefixes(path, Self.prefixes[.channel]!.map { [$0, "/"].joined() })
    }

    var channelID: String? {
        guard hasAnyOfPrefixes(path, ["channel/", "/channel/"]) else { return nil }

        return removePrefixes(path, Self.prefixes[.channel]!.map { [$0, "/"].joined() })
    }

    private var host: String {
        urlComponents?.host ?? ""
    }

    private var path: String {
        removePrefixes(urlComponents?.path ?? "", ["www.youtube.com", "youtube.com"])
    }

    private func hasAnyOfPrefixes(_ value: String, _ prefixes: [String]) -> Bool {
        prefixes.contains { value.hasPrefix($0) }
    }

    private func removePrefixes(_ value: String, _ prefixes: [String]) -> String {
        var value = value

        prefixes.forEach { prefix in
            if value.hasPrefix(prefix) {
                value.removeFirst(prefix.count)
            }
        }

        return value
    }

    private var queryItems: [URLQueryItem] {
        urlComponents?.queryItems ?? []
    }

    private func queryItemValue(_ name: String) -> String? {
        queryItems.first { $0.name == name }?.value
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
