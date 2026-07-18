//
//  VideoMetadataLine.swift
//  Yattee
//
//  View count and published date metadata line.
//

import SwiftUI

/// Displays video metadata: view count and/or published date with separator.
struct VideoMetadataLine: View {
    let viewCount: String?
    let publishedText: String?

    var body: some View {
        HStack(spacing: 4) {
            if let views = viewCount {
                Text("video.views \(views)")
            }
            if viewCount != nil && publishedText != nil {
                Text(verbatim: "•")
            }
            if let published = publishedText {
                Text(published)
            }
        }
    }
}

/// Compact metadata for small cards - shows just numbers without "views" word
/// and abbreviates time (e.g., "2d" instead of "2 days ago").
struct CompactVideoMetadataLine: View {
    let viewCount: String?
    let publishedText: String?

    var body: some View {
        HStack(spacing: 4) {
            if let views = viewCount {
                Text(views)
            }
            if viewCount != nil && publishedText != nil {
                Text(verbatim: "•")
            }
            if let published = publishedText {
                Text(abbreviateTime(published))
            }
        }
    }

    /// Converts "2 days ago" to "2d", "3 weeks ago" to "3w", etc.
    private func abbreviateTime(_ text: String) -> String {
        let lowercased = text.lowercased()

        // Handle common patterns
        let patterns: [(String, String)] = [
            ("second", "s"),
            ("minute", "m"),
            ("hour", "h"),
            ("day", "d"),
            ("week", "w"),
            ("month", "mo"),
            ("year", "y")
        ]

        for (unit, abbrev) in patterns {
            if lowercased.contains(unit) {
                // Extract the number
                let numbers = text.components(separatedBy: CharacterSet.decimalDigits.inverted).joined()
                if let number = numbers.first {
                    return "\(number)\(abbrev)"
                }
            }
        }

        // Fallback: return original but shortened if possible
        return text
            .replacingOccurrences(of: " ago", with: "")
            .replacingOccurrences(of: "Streamed ", with: "")
    }
}

// MARK: - Preview

#Preview {
    VStack(alignment: .leading, spacing: 8) {
        Text("Regular:")
        VideoMetadataLine(viewCount: "1.2M", publishedText: "2 days ago")
        VideoMetadataLine(viewCount: "500K", publishedText: nil)
        VideoMetadataLine(viewCount: nil, publishedText: "1 week ago")

        Divider()

        Text("Compact:")
        CompactVideoMetadataLine(viewCount: "1.2M", publishedText: "2 days ago")
        CompactVideoMetadataLine(viewCount: "500K", publishedText: nil)
        CompactVideoMetadataLine(viewCount: nil, publishedText: "1 week ago")
        CompactVideoMetadataLine(viewCount: "10K", publishedText: "3 hours ago")
        CompactVideoMetadataLine(viewCount: "5K", publishedText: "2 months ago")
    }
    .font(.caption)
    .foregroundStyle(.secondary)
    .padding()
}
