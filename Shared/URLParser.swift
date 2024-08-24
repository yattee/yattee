import CoreMedia
import Foundation

struct URLParser {
    static var shortsPrefix = "/shorts/"
    static let prefixes: [Destination: [String]] = [
        .playlist: ["/playlist", "playlist"],
        .channel: ["/c", "c", "/channel", "channel", "/user", "user"],
        .search: ["/results", "search"]
    ]

    enum Destination {
        case fileURL, video, playlist, channel, search
        case favorites, subscriptions, popular, trending
    }

    var url: URL
    var allowFileURLs = true

    init(url: URL, allowFileURLs: Bool = true) {
        self.url = url
        self.allowFileURLs = allowFileURLs
        let urlString = url.absoluteString
        let scheme = urlComponents?.scheme
        if scheme == nil,
           urlString.contains("youtube.com") ||
           urlString.contains("youtu.be") ||
           urlString.contains("youtube-nocookie.com"),
           let url = URL(string: "https://\(urlString)")
        {
            self.url = url
        }
    }

    var destination: Destination? {
        if hasAnyOfPrefixes(path, ["favorites"]) { return .favorites }
        if hasAnyOfPrefixes(path, ["subscriptions"]) { return .subscriptions }
        if hasAnyOfPrefixes(path, ["popular"]) { return .popular }
        if hasAnyOfPrefixes(path, ["trending"]) { return .trending }

        if hasAnyOfPrefixes(path, Self.prefixes[.playlist]!) ||
            queryItemValue("v") == "playlist" ||
            (queryItemValue("list") ?? "").count > 3
        {
            return .playlist
        }
        if hasAnyOfPrefixes(path, Self.prefixes[.channel]!) {
            return .channel
        }
        if hasAnyOfPrefixes(path, Self.prefixes[.search]!) {
            return .search
        }

        guard let id = videoID, !id.isEmpty else {
            if isYoutubeHost {
                return .channel
            }

            return allowFileURLs ? .fileURL : nil
        }

        return .video
    }

    var isYoutubeHost: Bool {
        guard let urlComponents else { return false }
        let hostComponents = (urlComponents.host ?? "").components(separatedBy: ".").prefix(2)

        if hostComponents.contains("youtube") || hostComponents.contains("youtube-nocookie") {
            return true
        }

        let host = hostComponents.joined(separator: ".")
            .replacingFirstOccurrence(of: "www.", with: "")

        return host == "youtu.be"
    }

    var isYoutube: Bool {
        guard let urlComponents else { return false }

        return urlComponents.host == "youtube.com" || urlComponents.host == "www.youtube.com" || urlComponents.host == "youtu.be"
    }

    var isShortsPath: Bool {
        path.hasPrefix(Self.shortsPrefix)
    }

    var fileURL: URL? {
        guard allowFileURLs, destination == .fileURL else { return nil }
        return url
    }

    var videoID: String? {
        if host == "youtu.be", !path.isEmpty {
            return String(path.suffix(from: path.index(path.startIndex, offsetBy: 1)))
        }

        if isYoutubeHost, isShortsPath {
            let index = path.index(path.startIndex, offsetBy: Self.shortsPrefix.count)
            return String(path[index...])
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
        guard hasAnyOfPrefixes(path, ["c/", "/c/"]) else {
            if channelID == nil, username == nil { return pathWithoutForwardSlash }
            return nil
        }
        return removePrefixes(path, Self.prefixes[.channel]!.map { [$0, "/"].joined() })
    }

    var channelID: String? {
        guard hasAnyOfPrefixes(path, ["channel/", "/channel/"]) else { return nil }

        return removePrefixes(path, Self.prefixes[.channel]!.map { [$0, "/"].joined() })
    }

    var username: String? {
        guard hasAnyOfPrefixes(path, ["user/", "/user/"]) else { return nil }

        return removePrefixes(path, ["user/", "/user/"])
    }

    private var host: String {
        urlComponents?.host ?? ""
    }

    private var pathWithoutForwardSlash: String {
        guard let urlComponents else { return "" }

        return String(urlComponents.path.dropFirst())
    }

    private var path: String {
        removePrefixes(urlComponents?.path ?? "", ["www.youtube.com", "youtube.com"])
    }

    private func hasAnyOfPrefixes(_ value: String, _ prefixes: [String]) -> Bool {
        prefixes.contains { value.hasPrefix($0) }
    }

    private func removePrefixes(_ value: String, _ prefixes: [String]) -> String {
        var value = value

        for prefix in prefixes where value.hasPrefix(prefix) {
            value.removeFirst(prefix.count)
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
