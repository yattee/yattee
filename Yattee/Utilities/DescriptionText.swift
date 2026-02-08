//
//  DescriptionText.swift
//  Yattee
//
//  Utilities for parsing and formatting video description text with clickable links and timestamps.
//

import Foundation
import SwiftUI

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

extension View {
    /// Adds a URL handler that intercepts timestamp links and seeks the player.
    func handleTimestampLinks(using playerService: PlayerService?) -> some View {
        self.environment(\.openURL, OpenURLAction { url in
            if let seconds = DescriptionText.seekSeconds(from: url) {
                Task {
                    await playerService?.seek(to: TimeInterval(seconds))
                }
                return .handled
            }
            return .systemAction
        })
    }
}
