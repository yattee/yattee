//
//  DescriptionText.swift
//  Yattee
//
//  Utilities for parsing and formatting video description text with clickable links and timestamps.
//

import Foundation
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif
#if canImport(AppKit)
import AppKit
#endif

// MARK: - Description Text Utilities

enum DescriptionText {
    /// Creates an attributed string with clickable URLs and timestamps.
    /// Timestamps are converted to `yattee-seek://SECONDS` URLs.
    static func attributed(_ text: String, linkColor: Color = .accentColor) -> AttributedString {
        var attributedString = AttributedString(text)

        // URL regex pattern
        let urlPattern = #"https?://[^\s<>\"\']+"#

        if let regex = try? NSRegularExpression(pattern: urlPattern, options: []) {
            let nsRange = NSRange(text.startIndex..., in: text)
            let matches = regex.matches(in: text, options: [], range: nsRange)

            for match in matches {
                guard let range = Range(match.range, in: text),
                      let attributedRange = Range(range, in: attributedString),
                      let url = URL(string: String(text[range])) else {
                    continue
                }

                attributedString[attributedRange].link = url
                attributedString[attributedRange].foregroundColor = linkColor
            }
        }

        // Timestamp pattern: matches formats like 0:00, 00:00, 0:00:00, 00:00:00
        // Must be at word boundary (not part of a larger number sequence)
        let timestampPattern = #"(?<![:\d])(\d{1,2}:\d{2}(?::\d{2})?)(?![:\d])"#

        if let timestampRegex = try? NSRegularExpression(pattern: timestampPattern, options: []) {
            let nsRange = NSRange(text.startIndex..., in: text)
            let matches = timestampRegex.matches(in: text, options: [], range: nsRange)

            for match in matches {
                guard let range = Range(match.range, in: text),
                      let attributedRange = Range(range, in: attributedString) else {
                    continue
                }

                let timestampString = String(text[range])
                let seconds = parseTimestamp(timestampString)

                if let url = URL(string: "yattee-seek://\(seconds)") {
                    attributedString[attributedRange].link = url
                    attributedString[attributedRange].foregroundColor = linkColor
                }
            }
        }

        return attributedString
    }

    /// Parses a timestamp string (MM:SS or H:MM:SS) into total seconds.
    static func parseTimestamp(_ timestamp: String) -> Int {
        let components = timestamp.split(separator: ":").compactMap { Int($0) }
        switch components.count {
        case 2: // MM:SS
            return components[0] * 60 + components[1]
        case 3: // H:MM:SS
            return components[0] * 3600 + components[1] * 60 + components[2]
        default:
            return 0
        }
    }

    /// URL scheme used for seek timestamps.
    static let seekScheme = "yattee-seek"

    /// Extracts the seconds value from a seek URL, if valid.
    static func seekSeconds(from url: URL) -> Int? {
        guard url.scheme == seekScheme else { return nil }
        return Int(url.host ?? "")
    }
}

// MARK: - OpenURL Action for Seeking

/// Opens `url` in the user's default system browser (Safari on iOS/tvOS,
/// default browser on macOS). Used as the fallback when short-link resolution
/// fails or the destination isn't a URL the app can handle.
@MainActor
private func openInSystemBrowser(_ url: URL) {
    #if canImport(UIKit) && !os(watchOS)
    UIApplication.shared.open(url)
    #elseif canImport(AppKit)
    NSWorkspace.shared.open(url)
    #endif
}

extension View {
    /// Adds a URL handler that intercepts timestamp links (seeks the player) and
    /// known content URLs — YouTube/PeerTube video/channel/playlist links and external
    /// video URLs — so they open in-app instead of the browser.
    ///
    /// When the user has enabled "Resolve Short Links" in YouTube Enhancements,
    /// taps on known URL shorteners (bit.ly, tinyurl, t.co, …) whose hosts aren't
    /// themselves routable are resolved asynchronously: if the redirect target is
    /// a supported URL, it's opened in-app; otherwise we fall back to the system
    /// browser with the original URL.
    func handleTimestampLinks(using playerService: PlayerService?) -> some View {
        self.modifier(HandleTimestampLinksModifier(playerService: playerService))
    }
}

private struct HandleTimestampLinksModifier: ViewModifier {
    let playerService: PlayerService?
    @Environment(\.appEnvironment) private var appEnvironment

    func body(content: Content) -> some View {
        let resolveShortLinks = appEnvironment?.settingsManager.resolveShortLinksEnabled ?? false
        return content.environment(\.openURL, OpenURLAction { url in
            if let seconds = DescriptionText.seekSeconds(from: url) {
                Task {
                    await playerService?.seek(to: TimeInterval(seconds))
                }
                return .handled
            }

            let router = URLRouter()

            // 1. Definitely-playable URLs (YouTube / PeerTube / direct media /
            //    custom scheme) open in-app without any prompt.
            if router.routeConfidently(url) != nil {
                NotificationCenter.default.post(name: .openDescriptionLink, object: url)
                return .handled
            }

            // 2. URL shorteners — resolve first, *then* decide. This has to run
            //    before the loose `route()` check below, because `route()` would
            //    otherwise match bit.ly/t.co/etc. as `.externalVideo` and send
            //    the *shortener* URL itself to yt-dlp.
            if resolveShortLinks && URLShortenerResolver.isShortener(url) {
                Task { @MainActor in
                    guard let resolved = await URLShortenerResolver.resolve(url) else {
                        openInSystemBrowser(url)
                        return
                    }

                    if router.routeConfidently(resolved) != nil {
                        NotificationCenter.default.post(name: .openDescriptionLink, object: resolved)
                    } else {
                        // Ambiguous destination (e.g. a news article). Let the user
                        // decide whether to try opening in Yattee (falls back to
                        // yt-dlp extraction) or in the system browser.
                        NotificationCenter.default.post(name: .promptResolvedShortLink, object: resolved)
                    }
                }
                return .handled
            }

            // 3. Non-shortener URLs that only match via the loose `.externalVideo`
            //    fallback (e.g. vimeo.com/…, news articles, any http(s)): we
            //    can't tell whether yt-dlp will successfully extract, so ask
            //    the user whether to try extracting or open in the browser.
            if router.routeConfidently(url) == nil, router.route(url) != nil {
                NotificationCenter.default.post(name: .promptAmbiguousExternalLink, object: url)
                return .handled
            }

            return .systemAction
        })
    }
}
