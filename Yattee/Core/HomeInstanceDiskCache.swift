//
//  HomeInstanceDiskCache.swift
//  Yattee
//
//  Persistent on-device cache for home instance content (Popular/Trending).
//  Stores cached videos on disk to enable fast loading on app launch.
//

import Foundation

/// Persistent cache for home instance content that stores videos on disk.
/// This is a local-only cache (not synced to iCloud) for fast content loading.
actor HomeInstanceDiskCache {
    static let shared = HomeInstanceDiskCache()

    private let fileManager = FileManager.default
    private let cacheDirectory: URL
    private let cacheFileName = "library_instances.json"

    /// In-memory cache of the data.
    private var cachedData: CacheData?

    private init() {
        // Use Caches directory - not backed up, not synced
        let caches = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first!
        cacheDirectory = caches.appendingPathComponent("LibraryCache", isDirectory: true)

        try? fileManager.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }

    private var cacheFileURL: URL {
        cacheDirectory.appendingPathComponent(cacheFileName)
    }

    // MARK: - Public API

    /// Loads the cached data from disk.
    /// Returns nil if no cache exists or if it's corrupted.
    func load() async -> CacheData? {
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
            let cacheData = try decoder.decode(CacheData.self, from: data)

            // Store in memory
            cachedData = cacheData
            return cacheData
        } catch {
            // Cache is corrupted, remove it
            try? fileManager.removeItem(at: cacheFileURL)
            await MainActor.run {
                LoggingService.shared.warning(
                    "HomeInstanceDiskCache.load: Cache corrupted, removed",
                    category: .general,
                    details: error.localizedDescription
                )
            }
            return nil
        }
    }

    /// Saves the cache to disk.
    func save(_ data: CacheData) async {
        // Update in-memory cache
        cachedData = data

        // Write to disk
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = .prettyPrinted
            let encodedData = try encoder.encode(data)
            let sizeMB = Double(encodedData.count) / (1024 * 1024)
            try encodedData.write(to: cacheFileURL, options: .atomic)
            await MainActor.run {
                LoggingService.shared.debug(
                    "HomeInstanceDiskCache.save: Wrote \(data.videos.values.map { $0.count }.reduce(0, +)) videos (\(String(format: "%.2f", sizeMB)) MB) to disk",
                    category: .general
                )
            }
        } catch {
            await MainActor.run {
                LoggingService.shared.error(
                    "HomeInstanceDiskCache.save: Failed to write to disk",
                    category: .general,
                    details: error.localizedDescription
                )
            }
        }
    }

    /// Clears the cache from both memory and disk.
    func clear() async {
        cachedData = nil
        try? fileManager.removeItem(at: cacheFileURL)
        await MainActor.run {
            LoggingService.shared.debug("HomeInstanceDiskCache.clear: Cache cleared", category: .general)
        }
    }
}

// MARK: - Cache Data Model

extension HomeInstanceDiskCache {
    /// Data structure for the home instance cache.
    /// Uses cache keys in format "instanceID_contentType" (e.g., "UUID_popular")
    struct CacheData: Codable, Sendable {
        var videos: [String: [Video]]  // cacheKey -> videos
        var lastUpdated: [String: Date]  // cacheKey -> timestamp
        
        init(videos: [String: [Video]] = [:], lastUpdated: [String: Date] = [:]) {
            self.videos = videos
            self.lastUpdated = lastUpdated
        }
    }
}
