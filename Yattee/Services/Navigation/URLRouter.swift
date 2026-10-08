//
//  URLRouter.swift
//  Yattee
//
//  URL parsing and routing for deep links and shared URLs.
//

import Foundation

/// Routes URLs to navigation destinations.
struct URLRouter: Sendable {

    // MARK: - Main Routing

    /// Route a URL only if we are *confident* the app can handle it natively —
    /// YouTube/PeerTube video/channel/playlist, direct media (mp4/m3u8/etc),
    /// or the custom `yattee://` scheme. Unlike `route(_:)` this deliberately
    /// skips the `.externalVideo` yt-dlp fallback, which matches almost any
    /// http/https URL and is therefore unsafe to trigger blindly after
    /// resolving a URL shortener.
    func routeConfidently(_ url: URL) -> NavigationDestination? {
        guard let destination = route(url) else { return nil }
        if case .externalVideo = destination { return nil }
        return destination
    }

    /// Route a URL to a navigation destination.
    func route(_ url: URL) -> NavigationDestination? {
        // Resolve yattee://open?url=… wrappers up front so every caller gets the
        // inner URL intact (including its own `&t=` / `&list=` query items).
        let url = unwrapped(url)

        // Try custom scheme first
        if url.scheme?.lowercased() == "yattee" {
            return parseCustomScheme(url)
        }

        // Try PeerTube playlist URLs before video URLs (`/w/p/{id}` would otherwise
        // parse as a video named "p")
        if let (instance, playlistID) = parsePeerTubePlaylistURL(url) {
            return .playlist(.remote(PlaylistID(source: .federated(provider: ContentSource.peertubeProvider, instance: instance), playlistID: playlistID), instance: nil))
        }

        // Try YouTube playlist URLs first (before video URLs since playlist pages can have v= param)
        if let playlistID = parseYouTubePlaylistURL(url) {
            return .playlist(.remote(PlaylistID(source: .global(provider: ContentSource.youtubeProvider), playlistID: playlistID), instance: nil))
        }

        // Try YouTube channel URLs
        if let channelID = parseYouTubeChannelURL(url) {
            return .channel(channelID, .global(provider: ContentSource.youtubeProvider))
        }

        // Try YouTube video URLs
        if let videoID = parseYouTubeURL(url) {
            return .video(.id(.global(videoID)))
        }

        // youtube.com/results?search_query=…
        if let query = parseYouTubeSearchURL(url) {
            return .search(query)
        }

        // YouTube pages that hold no video (home, feeds, hashtags, Music
        // browse pages) go nowhere rather than to a yt-dlp extraction that
        // can only fail
        if isYouTubeNonVideoPage(url) {
            return nil
        }

        // Try PeerTube URLs
        if let (instance, videoID) = parsePeerTubeURL(url) {
            return .video(.id(.federated(videoID, instance: instance, uuid: nil)))
        }

        // Try direct media URLs (mp4, m3u8, etc.) - no extraction needed.
        // Remote only: a link from another app must never open a local file.
        if isHTTPURL(url), DirectMediaHelper.isDirectMediaURL(url) {
            return .directMedia(url)
        }

        // Fallback: Try external URL extraction for any http/https URL
        // This will be handled by Yattee Server using yt-dlp
        if isExternalVideoURL(url) {
            return .externalVideo(url)
        }

        return nil
    }

    // MARK: - External URL Detection

    /// Check if URL might be an external video that yt-dlp can handle.
    private func isHTTPURL(_ url: URL) -> Bool {
        let scheme = url.scheme?.lowercased()
        return scheme == "http" || scheme == "https"
    }

    private func isExternalVideoURL(_ url: URL) -> Bool {
        // Must be http or https
        guard isHTTPURL(url) else {
            return false
        }

        // Must have a host
        guard let host = url.host?.lowercased(), !host.isEmpty else {
            return false
        }

        // Skip known non-video sites
        let excludedHosts = [
            "google.com", "www.google.com",
            "bing.com", "www.bing.com",
            "duckduckgo.com", "www.duckduckgo.com",
            "apple.com", "www.apple.com",
            "github.com", "www.github.com"
        ]

        if excludedHosts.contains(host) {
            return false
        }

        return true
    }

    // MARK: - Wrapper Unwrapping

    /// Resolve a `yattee://open?url={encoded_url}` wrapper (share extension) to the inner URL.
    /// Returns the input unchanged for any other URL. The wrapper's query holds the full
    /// original link, so timestamp parsing must run against the unwrapped URL.
    ///
    /// The share extension encodes with `.urlQueryAllowed`, which leaves `?`, `&`, and `=`
    /// intact - URLComponents would split the inner URL's own query into separate wrapper
    /// items (losing e.g. `&t=120`), so take the raw remainder after `?url=` instead.
    func unwrapped(_ url: URL) -> URL {
        guard url.scheme?.lowercased() == "yattee", url.host == "open",
              let range = url.absoluteString.range(of: "?url=") else {
            return url
        }
        let raw = String(url.absoluteString[range.upperBound...])
        guard let decoded = raw.removingPercentEncoding,
              let innerURL = URL(string: decoded) else {
            return url
        }
        // Unwrap once more in case the wrapper was itself wrapped
        if innerURL.scheme?.lowercased() == "yattee", innerURL.host == "open", innerURL != url {
            return unwrapped(innerURL)
        }
        return innerURL
    }

    // MARK: - Timestamp Parsing

    /// Extract a timestamp (seconds) from a URL's query, supporting `t`, `time`, and `start`.
    /// Accepts plain seconds (`90`, `90.5`), YouTube-style `90s`, and `1h2m3s` / `2m30s` forms.
    func parseTimestamp(_ url: URL) -> TimeInterval? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let items = components.queryItems else {
            return nil
        }
        for name in ["t", "time", "start"] {
            if let raw = items.first(where: { $0.name == name })?.value,
               let parsed = Self.parseTimestampValue(raw) {
                return parsed
            }
        }
        return nil
    }

    /// Parse a single timestamp string. Returns nil if unparseable or zero-length.
    static func parseTimestampValue(_ raw: String) -> TimeInterval? {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }

        // Plain numeric value (e.g. "90", "90.5"). Reject non-finite values
        // ("inf"/"infinity"/"nan") that `TimeInterval(_:)` accepts — a `?t=inf`
        // link would otherwise seek the player to `Double.infinity`.
        if let value = TimeInterval(trimmed) {
            return (value.isFinite && value >= 0) ? value : nil
        }

        // Compound form like "1h2m3s", "2m30s", "90s"
        var total: TimeInterval = 0
        var current = ""
        var matched = false
        for ch in trimmed {
            if ch.isNumber || ch == "." {
                current.append(ch)
            } else {
                guard let value = TimeInterval(current) else { return nil }
                let unit: TimeInterval
                switch ch {
                case "h", "H": unit = 3600
                case "m", "M": unit = 60
                case "s", "S": unit = 1
                default: return nil
                }
                total += value * unit
                current = ""
                matched = true
            }
        }
        // Trailing digits without a unit suffix (e.g. "1m30") — treat as seconds.
        if !current.isEmpty, let value = TimeInterval(current) {
            total += value
            matched = true
        }
        return matched ? total : nil
    }

    // MARK: - Custom Scheme

    /// Parse yattee:// scheme URLs.
    private func parseCustomScheme(_ url: URL) -> NavigationDestination? {
        guard let host = url.host?.lowercased() else { return parseLegacyScheme(url) }

        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)

        switch host {
        case "video":
            // yattee://video/{videoId}?source={source}&instance={url}
            let videoID = url.lastPathComponent
            guard !videoID.isEmpty else { return nil }

            let sourceParam = components?.queryItems?.first(where: { $0.name == "source" })?.value

            if sourceParam == "peertube",
               let instanceStr = components?.queryItems?.first(where: { $0.name == "instance" })?.value,
               let instanceURL = URL(string: instanceStr) {
                return .video(.id(.federated(videoID, instance: instanceURL, uuid: nil)))
            }

            return .video(.id(.global(videoID)))

        case "channel":
            // yattee://channel/{channelId}?source={source}&instance={url}
            let channelID = url.lastPathComponent
            guard !channelID.isEmpty else { return nil }

            let sourceParam = components?.queryItems?.first(where: { $0.name == "source" })?.value
            let source: ContentSource
            if sourceParam == "peertube",
               let instanceStr = components?.queryItems?.first(where: { $0.name == "instance" })?.value,
               let instanceURL = URL(string: instanceStr) {
                source = .federated(provider: ContentSource.peertubeProvider, instance: instanceURL)
            } else {
                source = .global(provider: ContentSource.youtubeProvider)
            }

            return .channel(channelID, source)

        case "playlist":
            // yattee://playlist/{playlistId}?source={source}&instance={url}
            let playlistID = url.lastPathComponent
            // yattee://playlist?list=… is the 1.x form
            guard !playlistID.isEmpty, playlistID != "/" else { return parseLegacyScheme(url) }

            let sourceParam = components?.queryItems?.first(where: { $0.name == "source" })?.value
            let source: ContentSource
            if sourceParam == "peertube",
               let instanceStr = components?.queryItems?.first(where: { $0.name == "instance" })?.value,
               let instanceURL = URL(string: instanceStr) {
                source = .federated(provider: ContentSource.peertubeProvider, instance: instanceURL)
            } else {
                source = .global(provider: ContentSource.youtubeProvider)
            }
            return .playlist(.remote(PlaylistID(source: source, playlistID: playlistID), instance: nil))

        case "search":
            // yattee://search?q={query}
            guard let query = components?.queryItems?.first(where: { $0.name == "q" })?.value,
                  !query.isEmpty else {
                return nil
            }
            return .search(query)

        case "playlists":
            // yattee://playlists
            return .playlists

        case "bookmarks":
            // yattee://bookmarks
            return .bookmarks

        case "history":
            // yattee://history
            return .history

        case "downloads":
            // yattee://downloads
            return .downloads

        case "channels":
            // yattee://channels (manage subscribed channels)
            return .manageChannels

        case "subscriptions":
            // yattee://subscriptions
            return .subscriptionsFeed

        case "continue-watching":
            // yattee://continue-watching
            return .continueWatching

        case "settings":
            // yattee://settings
            return .settings

        case "open":
            // yattee://open?url={encoded_url} - from share extension. `route()` unwraps
            // well-formed wrappers before getting here; this is a wrapper with no
            // usable inner URL.
            return nil

        default:
            // Action hosts (yattee://play, yattee://player/…) are LinkActionParser's
            if LinkActionParser.hosts.contains(host) { return nil }
            return parseLegacyScheme(url)
        }
    }

    /// Yattee 1.x accepted any web link with its scheme swapped for `yattee://`
    /// (`yattee://youtube.com/watch?v=…`, `yattee://https://youtu.be/…`) and bare
    /// paths (`yattee://watch?v=…`). Shortcuts and automations built for 1.x still
    /// send these, so rewrite them to https and route them as web links.
    private func parseLegacyScheme(_ url: URL) -> NavigationDestination? {
        let absolute = url.absoluteString
        guard let separator = absolute.range(of: "://") else { return nil }
        var remainder = String(absolute[separator.upperBound...])

        // yattee://https://… — the original URL was appended whole
        if remainder.lowercased().hasPrefix("https://") || remainder.lowercased().hasPrefix("http://") {
            return routeLegacyWebURL(remainder)
        }
        // yattee://https//… — some URL encoders drop the colon
        for prefix in ["https//", "http//"] where remainder.lowercased().hasPrefix(prefix) {
            remainder = String(remainder.dropFirst(prefix.count))
        }

        // yattee://watch?v=…, yattee://shorts/…, yattee://playlist?list=… — bare YouTube paths
        let host = remainder.prefix { $0 != "/" && $0 != "?" && $0 != "#" }
        if !host.contains(".") {
            return routeLegacyWebURL("https://www.youtube.com/\(remainder)")
        }
        return routeLegacyWebURL("https://\(remainder)")
    }

    /// Only accept rewritten legacy links that resolve to something Yattee handles
    /// natively — never the yt-dlp catch-all, so `yattee://anything` stays a no-op.
    /// PeerTube-shaped paths (`yattee://host.tld/w/{id}`) pass too, as they do as web links.
    private func routeLegacyWebURL(_ string: String) -> NavigationDestination? {
        guard let webURL = URL(string: string), isHTTPURL(webURL) else { return nil }
        return routeConfidently(webURL)
    }

    // MARK: - YouTube URL Parsing

    /// Whether the host is YouTube's: youtube.com and its subdomains (www, m,
    /// music), youtube-nocookie.com, youtu.be. Exact, so look-alike hosts such
    /// as `notyoutube.com` don't match.
    func isYouTubeHost(_ host: String?) -> Bool {
        guard let host = host?.lowercased() else { return false }
        return host == "youtu.be"
            || host == "youtube.com" || host.hasSuffix(".youtube.com")
            || host == "youtube-nocookie.com" || host.hasSuffix(".youtube-nocookie.com")
    }

    /// The playlist a YouTube watch link plays the video within
    /// (`watch?v=X&list=Y`), when it is a real playlist. Mixes (`RD…`) and
    /// private lists (Liked, Watch Later) can't be opened as playlists.
    func youTubePlaylistContext(_ url: URL) -> String? {
        guard isYouTubeHost(url.host), parseYouTubeURL(url) != nil,
              let listID = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "list" })?.value,
              !listID.isEmpty,
              !listID.hasPrefix("RD"),
              !["LL", "WL", "LM"].contains(listID) else {
            return nil
        }
        return listID
    }

    /// Parse `youtube.com/results?search_query=…` into the search query.
    private func parseYouTubeSearchURL(_ url: URL) -> String? {
        guard isYouTubeHost(url.host), url.path == "/results" || url.path == "/search" else { return nil }
        // Raw items: form encoding writes spaces as `+`, which must become
        // spaces before percent-decoding (an encoded `%2B` stays a plus)
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.percentEncodedQueryItems
        let query = (items?.first(where: { $0.name == "search_query" }) ?? items?.first(where: { $0.name == "q" }))?
            .value?
            .replacingOccurrences(of: "+", with: " ")
            .removingPercentEncoding?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let query, !query.isEmpty else { return nil }
        return query
    }

    /// YouTube pages that are not a video, playlist, channel or search.
    private func isYouTubeNonVideoPage(_ url: URL) -> Bool {
        guard isYouTubeHost(url.host), url.host?.lowercased() != "youtu.be" else { return false }
        let path = url.pathComponents.dropFirst()
        guard let first = path.first?.lowercased() else { return true } // home page
        return ["feed", "hashtag", "results", "search", "browse", "account", "premium", "explore", "gaming", "watch"]
            .contains(first)
    }

    /// Parse YouTube URLs and extract video ID.
    private func parseYouTubeURL(_ url: URL) -> String? {
        let host = url.host?.lowercased() ?? ""

        // youtube.com/watch?v=VIDEO_ID (also youtube-nocookie.com/embed/VIDEO_ID)
        if isYouTubeHost(host), host != "youtu.be" {
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
            if let videoID = components?.queryItems?.first(where: { $0.name == "v" })?.value {
                return videoID
            }

            // youtube.com/shorts/VIDEO_ID
            if url.pathComponents.contains("shorts"),
               let index = url.pathComponents.firstIndex(of: "shorts"),
               url.pathComponents.count > index + 1 {
                return url.pathComponents[index + 1]
            }

            // youtube.com/embed/VIDEO_ID
            if url.pathComponents.contains("embed"),
               let index = url.pathComponents.firstIndex(of: "embed"),
               url.pathComponents.count > index + 1 {
                return url.pathComponents[index + 1]
            }

            // youtube.com/live/VIDEO_ID
            if url.pathComponents.contains("live"),
               let index = url.pathComponents.firstIndex(of: "live"),
               url.pathComponents.count > index + 1 {
                return url.pathComponents[index + 1]
            }
        }

        // youtu.be/VIDEO_ID
        if host == "youtu.be" {
            let videoID = url.lastPathComponent
            if !videoID.isEmpty && videoID != "/" {
                return videoID
            }
        }

        // m.youtube.com
        if host == "m.youtube.com" {
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
            return components?.queryItems?.first(where: { $0.name == "v" })?.value
        }

        return nil
    }

    // MARK: - PeerTube URL Parsing

    /// Parse PeerTube URLs and extract instance URL and video ID.
    private func parsePeerTubeURL(_ url: URL) -> (URL, String)? {
        // PeerTube URLs are typically:
        // https://instance.tld/w/VIDEO_ID
        // https://instance.tld/videos/watch/VIDEO_ID

        guard let host = url.host,
              let scheme = url.scheme else {
            return nil
        }

        // Skip known non-PeerTube hosts
        let nonPeerTubeHosts = [
            "youtube.com", "www.youtube.com", "m.youtube.com",
            "youtu.be", "music.youtube.com",
            "vimeo.com", "www.vimeo.com",
            "dailymotion.com", "www.dailymotion.com"
        ]

        if nonPeerTubeHosts.contains(host) {
            return nil
        }

        let pathComponents = url.pathComponents

        // /w/VIDEO_ID or /videos/watch/VIDEO_ID
        if pathComponents.contains("w") || pathComponents.contains("videos") {
            var videoID: String?

            if let wIndex = pathComponents.firstIndex(of: "w"),
               pathComponents.count > wIndex + 1 {
                videoID = pathComponents[wIndex + 1]
            } else if let watchIndex = pathComponents.firstIndex(of: "watch"),
                      pathComponents.count > watchIndex + 1 {
                videoID = pathComponents[watchIndex + 1]
            }

            if let videoID, !videoID.isEmpty {
                let instanceURL = URL(string: "\(scheme)://\(host)")!
                return (instanceURL, videoID)
            }
        }

        return nil
    }

    /// Parse PeerTube playlist URLs: `/w/p/{id}` and `/video-playlists/{id}`.
    private func parsePeerTubePlaylistURL(_ url: URL) -> (URL, String)? {
        guard let host = url.host, let scheme = url.scheme, isHTTPURL(url) else { return nil }
        let path = url.pathComponents

        var playlistID: String?
        if path.count >= 4, path[1] == "w", path[2] == "p" {
            playlistID = path[3]
        } else if path.count >= 3, path[1] == "video-playlists" {
            playlistID = path[2]
        }

        guard let playlistID, !playlistID.isEmpty,
              let instanceURL = URL(string: "\(scheme)://\(host)") else { return nil }
        return (instanceURL, playlistID)
    }

    // MARK: - Channel URL Parsing

    /// Parse YouTube channel URLs.
    func parseYouTubeChannelURL(_ url: URL) -> String? {
        let host = url.host?.lowercased() ?? ""

        guard isYouTubeHost(host), host != "youtu.be" else { return nil }

        let pathComponents = url.pathComponents

        // youtube.com/channel/CHANNEL_ID
        if let channelIndex = pathComponents.firstIndex(of: "channel"),
           pathComponents.count > channelIndex + 1 {
            return pathComponents[channelIndex + 1]
        }

        // youtube.com/@HANDLE
        if let component = pathComponents.first(where: { $0.hasPrefix("@") }) {
            return component
        }

        // youtube.com/c/CUSTOM_NAME
        if let cIndex = pathComponents.firstIndex(of: "c"),
           pathComponents.count > cIndex + 1 {
            return pathComponents[cIndex + 1]
        }

        // youtube.com/user/USERNAME
        if let userIndex = pathComponents.firstIndex(of: "user"),
           pathComponents.count > userIndex + 1 {
            return pathComponents[userIndex + 1]
        }

        return nil
    }

    // MARK: - Playlist URL Parsing

    /// Parse YouTube playlist URLs and extract playlist ID.
    private func parseYouTubePlaylistURL(_ url: URL) -> String? {
        let host = url.host?.lowercased() ?? ""

        guard isYouTubeHost(host), host != "youtu.be" else { return nil }

        // youtube.com/playlist?list=PLAYLIST_ID
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        if let listParam = components?.queryItems?.first(where: { $0.name == "list" })?.value {
            // Only return if this is primarily a playlist URL (path is /playlist)
            // or if there's no video ID (pure playlist link)
            let isPlaylistPath = url.pathComponents.contains("playlist")
            let hasVideoID = components?.queryItems?.first(where: { $0.name == "v" })?.value != nil

            // Return playlist ID only if it's a playlist page or watch page without video ID
            if isPlaylistPath || !hasVideoID {
                return listParam
            }
        }

        return nil
    }
}
