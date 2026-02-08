//
//  Storyboard.swift
//  Yattee
//
//  Represents storyboard sprite sheet data for video preview thumbnails.
//

import CoreGraphics
import Foundation

/// Represents a storyboard (sprite sheet) for video preview thumbnails.
struct Storyboard: Hashable, Sendable, Codable {
    /// Proxied URL path (e.g., /api/v1/storyboards/VIDEO_ID?width=160)
    /// This is the preferred URL as it goes through the instance proxy
    let proxyUrl: String?

    /// URL template for sprite sheets (contains M$M placeholder for sheet index)
    /// This is the direct YouTube URL which may be blocked
    let templateUrl: String

    /// Base URL of the instance (used to make proxyUrl absolute)
    let instanceBaseURL: URL?

    /// Width of each thumbnail in the grid
    let width: Int

    /// Height of each thumbnail in the grid
    let height: Int

    /// Total number of thumbnails across all sheets
    let count: Int

    /// Milliseconds between each thumbnail
    let interval: Int

    /// Number of columns in each sprite sheet grid
    let storyboardWidth: Int

    /// Number of rows in each sprite sheet grid
    let storyboardHeight: Int

    /// Total number of sprite sheet images
    let storyboardCount: Int

    // MARK: - Computed Properties

    /// Number of thumbnails per sprite sheet
    var thumbnailsPerSheet: Int {
        storyboardWidth * storyboardHeight
    }

    /// Interval between thumbnails in seconds
    var intervalSeconds: TimeInterval {
        TimeInterval(interval) / 1000.0
    }

    // MARK: - Methods

    /// Returns the URL for a specific sprite sheet index.
    /// Prefers proxied URL (goes through instance) over direct YouTube URL.
    /// - Parameter index: The sheet index (0-based)
    /// - Returns: URL for the sprite sheet, or nil if invalid
    func sheetURL(for index: Int) -> URL? {
        guard index >= 0, index < storyboardCount else { return nil }

        // Prefer proxied URL if available (goes through instance, not blocked)
        if let proxyUrl {
            // The proxy URL returns the full sprite sheet, append index parameter
            var urlString = proxyUrl
            if urlString.contains("?") {
                urlString += "&storyboard=\(index)"
            } else {
                urlString += "?storyboard=\(index)"
            }

            // Check if proxyUrl is already an absolute URL
            if urlString.hasPrefix("http://") || urlString.hasPrefix("https://") {
                return URL(string: urlString)
            }

            // Construct absolute URL from relative path (relative URLs don't work with URLSession)
            if let baseURL = instanceBaseURL {
                var baseString = baseURL.absoluteString
                if baseString.hasSuffix("/") && urlString.hasPrefix("/") {
                    baseString = String(baseString.dropLast())
                }
                let absoluteURLString = baseString + urlString
                return URL(string: absoluteURLString)
            }
        }

        // Fallback to templateUrl (direct YouTube URL, may be blocked)
        return directSheetURL(for: index)
    }

    /// Returns the direct URL for a specific sprite sheet index.
    /// Uses templateUrl directly, bypassing the proxy. Use for downloads.
    /// - Parameter index: The sheet index (0-based)
    /// - Returns: Direct URL for the sprite sheet, or nil if invalid
    func directSheetURL(for index: Int) -> URL? {
        guard index >= 0, index < storyboardCount else { return nil }
        let urlString = templateUrl.replacingOccurrences(of: "M$M", with: "\(index)")
        return URL(string: urlString)
    }

    /// Calculates the position of a thumbnail for a given timestamp.
    /// - Parameter time: The time in seconds
    /// - Returns: Tuple of (sheetIndex, row, column), or nil if time is out of range
    func position(for time: TimeInterval) -> (sheetIndex: Int, row: Int, column: Int)? {
        guard time >= 0, intervalSeconds > 0 else { return nil }

        let thumbnailIndex = Int(time / intervalSeconds)
        guard thumbnailIndex < count else { return nil }

        let sheetIndex = thumbnailIndex / thumbnailsPerSheet
        let positionInSheet = thumbnailIndex % thumbnailsPerSheet
        let row = positionInSheet / storyboardWidth
        let column = positionInSheet % storyboardWidth

        return (sheetIndex, row, column)
    }

    /// Calculates the crop rect for extracting a thumbnail at the given time.
    /// - Parameter time: The time in seconds
    /// - Returns: CGRect for cropping, or nil if time is out of range
    func cropRect(for time: TimeInterval) -> CGRect? {
        guard let position = position(for: time) else { return nil }

        return CGRect(
            x: CGFloat(position.column * width),
            y: CGFloat(position.row * height),
            width: CGFloat(width),
            height: CGFloat(height)
        )
    }
}

// MARK: - Local Storyboard Support

extension Storyboard {
    /// Creates a Storyboard configured for local file access.
    /// - Parameters:
    ///   - original: The original storyboard with metadata
    ///   - localDirectory: The directory URL containing downloaded sprite sheets
    /// - Returns: A new Storyboard with file:// URLs for local access
    static func localStoryboard(from original: Storyboard, localDirectory: URL) -> Storyboard {
        // Create template URL pointing to local files: sb_M$M.jpg
        let templatePath = localDirectory.appendingPathComponent("sb_M$M.jpg").absoluteString

        return Storyboard(
            proxyUrl: nil,  // No proxy for local files
            templateUrl: templatePath,
            instanceBaseURL: nil,
            width: original.width,
            height: original.height,
            count: original.count,
            interval: original.interval,
            storyboardWidth: original.storyboardWidth,
            storyboardHeight: original.storyboardHeight,
            storyboardCount: original.storyboardCount
        )
    }
}

// MARK: - Storyboard Selection

extension Array where Element == Storyboard {
    /// Selects the preferred storyboard based on desired width.
    /// Prefers the largest storyboard that doesn't exceed maxWidth.
    /// - Parameter maxWidth: Maximum preferred width (default 160)
    /// - Returns: Best matching storyboard, or nil if array is empty
    func preferred(maxWidth: Int = 160) -> Storyboard? {
        let suitable = filter { $0.width <= maxWidth }
        return suitable.max(by: { $0.width < $1.width }) ?? first
    }

    /// Returns the highest quality storyboard (largest width).
    func highest() -> Storyboard? {
        self.max(by: { $0.width < $1.width })
    }
}
