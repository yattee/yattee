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

    /// Route a URL to a navigation destination.
    func route(_ url: URL) -> NavigationDestination? {
        // Try custom scheme first
        if url.scheme == "yattee" {
            return parseCustomScheme(url)
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

        // Try PeerTube URLs
        if let (instance, videoID) = parsePeerTubeURL(url) {
            return .video(.id(.federated(videoID, instance: instance, uuid: nil)))
        }

        // Try direct media URLs (mp4, m3u8, etc.) - no extraction needed
        if DirectMediaHelper.isDirectMediaURL(url) {
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
    private func isExternalVideoURL(_ url: URL) -> Bool {
        // Must be http or https
        guard let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
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
            "duckduckgo.com",
            "apple.com", "www.apple.com",
            "github.com", "www.github.com"
        ]

        if excludedHosts.contains(host) {
            return false
        }

        return true
    }

    // MARK: - Custom Scheme

    /// Parse yattee:// scheme URLs.
    private func parseCustomScheme(_ url: URL) -> NavigationDestination? {
        guard let host = url.host else { return nil }

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
            // yattee://playlist/{playlistId}
            let playlistID = url.lastPathComponent
            guard !playlistID.isEmpty else { return nil }
            return .playlist(.remote(PlaylistID(source: .global(provider: ContentSource.youtubeProvider), playlistID: playlistID), instance: nil))

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
            // yattee://open?url={encoded_url} - from share extension
            if let urlParam = components?.queryItems?.first(where: { $0.name == "url" })?.value,
               let decodedURL = URL(string: urlParam) {
                // Route the decoded URL through normal routing
                return route(decodedURL)
            }
            return nil

        default:
            return nil
        }
    }

    // MARK: - YouTube URL Parsing

    /// Parse YouTube URLs and extract video ID.
    private func parseYouTubeURL(_ url: URL) -> String? {
        let host = url.host?.lowercased() ?? ""

        // youtube.com/watch?v=VIDEO_ID
        if host.contains("youtube.com") {
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

    // MARK: - Channel URL Parsing

    /// Parse YouTube channel URLs.
    func parseYouTubeChannelURL(_ url: URL) -> String? {
        let host = url.host?.lowercased() ?? ""

        guard host.contains("youtube.com") else { return nil }

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

        guard host.contains("youtube.com") else { return nil }

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
