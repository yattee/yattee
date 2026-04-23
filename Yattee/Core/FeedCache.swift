//
//  FeedCache.swift
//  Yattee
//
//  Persistent on-device feed cache for subscription videos.
//  Stores feed data on disk to enable fast loading on app launch.
//

import Foundation

/// Persistent feed cache that stores subscription videos on disk.
/// This is a local-only cache (not synced to iCloud) for fast feed loading.
actor FeedCache {
    static let shared = FeedCache()

    private let fileManager = FileManager.default
    private let cacheDirectory: URL
    private let cacheFileName = "subscription_feed.json"

    /// In-memory cache of the feed data.
    private var cachedData: FeedCacheData?

    private init() {
        // Use Caches directory - not backed up, not synced
        let caches = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first!
        cacheDirectory = caches.appendingPathComponent("FeedCache", isDirectory: true)

        try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }

    private var cacheFileURL: URL {
        cacheDirectory.appendingPathComponent(cacheFileName)
    }

    // MARK: - Public API

    /// Loads the cached feed from disk.
    /// Returns nil if no cache exists or if it's corrupted.
    func load() async -> FeedCacheData? {
        // Return in-memory cache if available
        if let cachedData {
            return cachedData
        }

        // Try to load from disk
        guard fileManager.fileExists(atPath: cacheFileURL.path) else {
            return nil
        }

        do {
            let data = try Data(contentsOf: cacheFileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let cacheData = try decoder.decode(FeedCacheData.self, from: data)

            // Store in memory
            cachedData = cacheData
            return cacheData
        } catch {
            // Cache is corrupted, remove it
            try? fileManager.removeItem(at: cacheFileURL)
            return nil
        }
    }

    /// Saves the feed to disk.
    func save(videos: [Video], lastUpdated: Date) async {
        let cacheData = FeedCacheData(videos: videos, lastUpdated: lastUpdated)

        // Update in-memory cache
        cachedData = cacheData

        // Write to disk
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(cacheData)
            let sizeMB = Double(data.count) / (1024 * 1024)
            try data.write(to: cacheFileURL, options: .atomic)
            await MainActor.run {
                LoggingService.shared.debug(
                    "FeedCache.save: Wrote \(videos.count) videos (\(String(format: "%.2f", sizeMB)) MB) to disk, lastUpdated: \(lastUpdated)",
                    category: .general
                )
            }
        } catch {
            await MainActor.run {
                LoggingService.shared.error(
                    "FeedCache.save: Failed to write to disk",
                    category: .general,
                    details: error.localizedDescription
                )
            }
        }
    }

    /// Clears the feed cache from both memory and disk.
    func clear() async {
        cachedData = nil
        try? fileManager.removeItem(at: cacheFileURL)
    }

    /// Invalidates the cache by clearing the lastUpdated timestamp.
    /// The cached videos remain available but will be considered stale.
    func invalidate() async {
        guard var data = cachedData else { return }
        data.lastUpdated = .distantPast
        cachedData = data
        await save(videos: data.videos, lastUpdated: .distantPast)
    }
}

// MARK: - Cache Data Model

/// Data structure for the feed cache.
struct FeedCacheData: Codable {
    var videos: [Video]
    var lastUpdated: Date
}
