//
//  ImageLoadingService.swift
//  Yattee
//
//  Configures Nuke's ImagePipeline for app-wide image loading.
//

import Foundation
import Nuke

/// Configures and manages the Nuke image loading pipeline.
@MainActor
final class ImageLoadingService: Sendable {
    static let shared = ImageLoadingService()

    private init() {}

    /// Configure the shared ImagePipeline with app-specific settings.
    /// Call this once at app launch.
    func configure() {
        // Memory cache limits (platform-specific)
        #if os(tvOS)
        let memoryCacheLimit = 50 * 1024 * 1024  // 50 MB
        #else
        let memoryCacheLimit = 100 * 1024 * 1024 // 100 MB
        #endif

        // Disk cache limits (platform-specific)
        #if os(tvOS)
        let diskCacheLimit = 100 * 1024 * 1024   // 100 MB
        #elseif os(macOS)
        let diskCacheLimit = 500 * 1024 * 1024   // 500 MB
        #else
        let diskCacheLimit = 300 * 1024 * 1024   // 300 MB (iOS)
        #endif

        // Create data cache
        let dataCache: DataCache? = {
            let cache = try? DataCache(name: "com.yattee.images")
            cache?.sizeLimit = diskCacheLimit
            return cache
        }()

        // Create image cache (memory)
        let imageCache = Nuke.ImageCache()
        imageCache.costLimit = memoryCacheLimit

        // Configure pipeline
        var config = ImagePipeline.Configuration()
        config.dataCache = dataCache
        config.imageCache = imageCache

        // Use default URLSession-based data loader
        config.dataLoader = DataLoader(configuration: .default)

        // Set as shared pipeline
        ImagePipeline.shared = ImagePipeline(configuration: config)

        LoggingService.shared.info(
            "Image pipeline configured",
            category: .imageLoading,
            details: "Memory: \(memoryCacheLimit / 1024 / 1024)MB, Disk: \(diskCacheLimit / 1024 / 1024)MB"
        )
    }

    /// Remove a specific URL from both the memory and disk image caches.
    /// Use when a previously cached URL is known to return stale or broken
    /// data (e.g. an expired proxied thumbnail URL).
    func removeCachedImage(for url: URL) {
        let request = ImageRequest(url: url)
        ImagePipeline.shared.cache.removeCachedImage(for: request)
        ImagePipeline.shared.cache.removeCachedData(for: request)
    }

    /// Clear all image caches (memory and disk).
    func clearCache() {
        // Clear memory cache
        ImagePipeline.shared.cache.removeAll()

        // Clear disk cache
        if let dataCache = ImagePipeline.shared.configuration.dataCache as? DataCache {
            dataCache.removeAll()
        }

        LoggingService.shared.info("Image cache cleared", category: .imageLoading)
    }

    /// Returns the disk cache size in bytes.
    func diskCacheSize() -> Int {
        guard let dataCache = ImagePipeline.shared.configuration.dataCache as? DataCache else {
            return 0
        }
        return dataCache.totalSize
    }

    /// Returns a formatted string of the disk cache size.
    func formattedDiskCacheSize() -> String {
        let size = diskCacheSize()
        return ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
    }
}
