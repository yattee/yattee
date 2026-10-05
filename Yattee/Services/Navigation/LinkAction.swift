//
//  LinkAction.swift
//  Yattee
//
//  URL scheme actions: links that do something rather than open a screen.
//
//    yattee://play?url={link}&t={seconds}
//    yattee://play-next?url={link}
//    yattee://queue?url={link}
//    yattee://download?url={link}
//    yattee://bookmark?url={link}
//    yattee://subscribe?url={channel link}
//    yattee://unsubscribe?url={channel link}
//    yattee://player/play | pause | toggle | next | previous | close
//    yattee://player/seek?t={seconds} | seek?by={±seconds}
//    yattee://player/rate?value={rate}
//
//  `url` may be percent-encoded or raw; a raw link keeps its own query
//  (`&list=…`) because only the action's own parameters end it.
//

import Foundation

/// An action requested through the URL scheme.
enum LinkAction: Equatable {
    case play(URL, startTime: TimeInterval?)
    case playNext(URL)
    case addToQueue(URL)
    case download(URL)
    case bookmark(URL)
    case subscribe(URL)
    case unsubscribe(URL)
    case player(PlayerCommand)

    enum PlayerCommand: Equatable {
        case play
        case pause
        case toggle
        case next
        case previous
        case close
        case seek(to: TimeInterval)
        case seekBy(TimeInterval)
        case rate(Double)
    }

    /// Whether the main window's sheets should go away first. Only actions
    /// that move the user somewhere do; queueing a video or pausing the
    /// player leaves whatever is on screen alone.
    var dismissesPresentations: Bool {
        if case .play = self { return true }
        return false
    }
}

/// What an action did, for callers that report back (x-callback-url).
enum LinkActionResult: Equatable {
    case success([String: String] = [:])
    case failure(code: String, message: String)
    case cancelled
}

// MARK: - Parsing

struct LinkActionParser {
    /// Parameters that belong to the action URL itself. Everything else
    /// after `url=` is part of the wrapped link.
    static let actionParameters: Set<String> = [
        "url", "t", "time", "start", "by", "value",
        "x-success", "x-error", "x-cancel", "x-source"
    ]

    /// Hosts claimed by actions, so `URLRouter` never reads them as 1.x links.
    static let hosts: Set<String> = [
        "play", "play-next", "queue", "download", "bookmark", "subscribe", "unsubscribe", "player"
    ]

    func parse(_ url: URL) -> LinkAction? {
        guard url.scheme?.lowercased() == "yattee",
              let host = url.host?.lowercased(), Self.hosts.contains(host) else {
            return nil
        }
        let query = Self.queryParameters(of: url)

        if host == "player" {
            return parsePlayerCommand(url: url, query: query)
        }

        guard let target = query["url"].flatMap(Self.targetURL) else { return nil }

        switch host {
        case "play":
            let outer = ["t", "time", "start"].lazy.compactMap { query[$0] }.first
                .flatMap(URLRouter.parseTimestampValue)
            return .play(target, startTime: outer ?? URLRouter().parseTimestamp(target))
        case "play-next":
            return .playNext(target)
        case "queue":
            return .addToQueue(target)
        case "download":
            return .download(target)
        case "bookmark":
            return .bookmark(target)
        case "subscribe":
            return .subscribe(target)
        case "unsubscribe":
            return .unsubscribe(target)
        default:
            return nil
        }
    }

    private func parsePlayerCommand(url: URL, query: [String: String]) -> LinkAction? {
        let verb = url.pathComponents.dropFirst().first?.lowercased() ?? ""
        switch verb {
        case "play": return .player(.play)
        case "pause": return .player(.pause)
        case "toggle": return .player(.toggle)
        case "next": return .player(.next)
        case "previous": return .player(.previous)
        case "close": return .player(.close)
        case "seek":
            if let raw = query["by"], let delta = Double(raw), delta.isFinite {
                return .player(.seekBy(delta))
            }
            if let raw = query["t"] ?? query["time"], let time = URLRouter.parseTimestampValue(raw) {
                return .player(.seek(to: time))
            }
            return nil
        case "rate":
            guard let raw = query["value"], let rate = Double(raw), rate.isFinite, rate > 0 else { return nil }
            return .player(.rate(rate))
        default:
            return nil
        }
    }

    /// The wrapped link: http(s) or a yattee:// screen link, never a local file.
    private static func targetURL(_ raw: String) -> URL? {
        // A raw link keeps its percent-escapes; an encoded one is decoded once.
        let string = raw.contains("://") ? raw : (raw.removingPercentEncoding ?? raw)
        guard let url = URL(string: string),
              let scheme = url.scheme?.lowercased(),
              ["http", "https", "yattee"].contains(scheme) else {
            return nil
        }
        return url
    }

    /// Splits the query on `&`, but keeps an unencoded `url=` value whole:
    /// it runs until the next parameter the action itself defines.
    static func queryParameters(of url: URL) -> [String: String] {
        let absolute = url.absoluteString
        guard let questionMark = absolute.firstIndex(of: "?") else { return [:] }
        let pieces = absolute[absolute.index(after: questionMark)...].split(separator: "&", omittingEmptySubsequences: false)

        var result: [String: String] = [:]
        var currentKey: String?
        for piece in pieces {
            let parts = piece.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            let key = (parts.first.map(String.init) ?? "").removingPercentEncoding ?? ""
            let value = parts.count > 1 ? String(parts[1]) : ""

            if currentKey == "url", !actionParameters.contains(key) {
                // Still inside the wrapped link
                result["url", default: ""] += "&" + piece
                continue
            }
            currentKey = key
            guard !key.isEmpty else { continue }
            // The wrapped link is decoded later, once the whole of it is known
            result[key] = key == "url" ? value : (value.replacingOccurrences(of: "+", with: " ").removingPercentEncoding ?? value)
        }
        return result
    }
}
