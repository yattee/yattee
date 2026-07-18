//
//  AvatarURLBuilder.swift
//  Yattee
//
//  Utility for constructing channel avatar URLs with Yattee Server fallback.
//

import Foundation
import Nuke

/// Utility for constructing channel avatar URLs with Yattee Server fallback
enum AvatarURLBuilder {
    
    /// Available avatar sizes on Yattee Server
    private static let availableSizes = [32, 48, 76, 100, 176, 512]
    
    /// Constructs the effective avatar URL for a channel
    /// - Parameters:
    ///   - channelID: The channel ID
    ///   - directURL: Direct avatar URL if available (from API response)
    ///   - serverURL: Yattee Server base URL
    ///   - size: Desired size in points (will be doubled for retina and rounded to nearest available)
    /// - Returns: URL to use for avatar, or nil if unavailable
    static func avatarURL(
        channelID: String,
        directURL: URL?,
        serverURL: URL?,
        size: Int
    ) -> URL? {
        // Check if this is a YouTube channel (UC prefix or @handle)
        let isYouTubeChannel = channelID.hasPrefix("UC") || channelID.hasPrefix("@")

        // Priority 1: For YouTube channels, prefer Yattee Server (more reliable, avoids stale URLs from iCloud sync)
        if isYouTubeChannel, let serverURL = serverURL {
            return buildServerAvatarURL(serverURL: serverURL, channelID: channelID, size: size)
        }

        // Priority 2: Use direct URL for non-YouTube channels or when server unavailable
        if let directURL = directURL {
            return directURL
        }

        // Priority 3: Try server as last resort (for YouTube without direct URL)
        if let serverURL = serverURL {
            return buildServerAvatarURL(serverURL: serverURL, channelID: channelID, size: size)
        }

        return nil
    }

    /// Builds the Yattee Server avatar URL for a channel
    private static func buildServerAvatarURL(serverURL: URL, channelID: String, size: Int) -> URL {
        // Calculate retina size and round to nearest available
        let retinaSize = size * 2
        let roundedSize = availableSizes
            .min { abs($0 - retinaSize) < abs($1 - retinaSize) } ?? 176

        return serverURL
            .appendingPathComponent("api/v1/channels")
            .appendingPathComponent(channelID)
            .appendingPathComponent("avatar")
            .appendingPathComponent("\(roundedSize).jpg")
    }

    /// Creates an ImageRequest with auth header for Yattee Server avatar URLs
    /// - Parameters:
    ///   - url: The avatar URL
    ///   - authHeader: Optional Basic Auth header for Yattee Server
    /// - Returns: ImageRequest configured with auth if needed, or nil if URL is nil
    static func imageRequest(url: URL?, authHeader: String?) -> ImageRequest? {
        guard let url else { return nil }
        var request = URLRequest(url: url)
        // Only add auth header for Yattee Server avatar URLs
        if let authHeader, url.path.contains("/api/v1/channels/") && url.path.contains("/avatar/") {
            request.setValue(authHeader, forHTTPHeaderField: "Authorization")
        }
        return ImageRequest(urlRequest: request)
    }
}
