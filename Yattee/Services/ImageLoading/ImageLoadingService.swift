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

    private let pipelineDelegate = TokenStrippingPipelineDelegate()

    private init() {}

    /// Returns a cache-stable key for an image URL by stripping query params
    /// that rotate per-request (e.g. Yattee-server signed `token`). Images
    /// whose path matches but token differs share a cache entry.
    nonisolated static func cacheKey(for url: URL) -> String {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url.absoluteString
        }
        if let items = components.queryItems {
            let filtered = items.filter { $0.name != "token" }
            components.queryItems = filtered.isEmpty ? nil : filtered
        }
        return components.url?.absoluteString ?? url.absoluteString
    }

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

        // Set as shared pipeline with a delegate that normalizes cache keys
        // so signed thumbnail URLs whose only difference is a rotating `token`
        // query param share a single cache entry.
        ImagePipeline.shared = ImagePipeline(configuration: config, delegate: pipelineDelegate)

        LoggingService.shared.info(
            "Image pipeline configured",
            category: .imageLoading,
            details: "Memory: \(memoryCacheLimit / 1024 / 1024)MB, Disk: \(diskCacheLimit / 1024 / 1024)MB"
        )
    }

    /// Warm the image cache for the given URL so a subsequent `LazyImage`
    /// display hits the cache instantly. Returns after the image is cached
    /// or the operation fails (silently). Bounded by `timeout` seconds.
    nonisolated func prefetchImage(for url: URL, timeout: TimeInterval = 3) async {
        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                _ = try? await ImagePipeline.shared.image(for: url)
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
            }
            await group.next()
            group.cancelAll()
        }
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

/// Pipeline delegate that normalizes Nuke's cache key by stripping per-request
/// query params (`token`). Prevents churn when Yattee-server re-signs URLs.
private final class TokenStrippingPipelineDelegate: ImagePipelineDelegate {
    func cacheKey(for request: ImageRequest, pipeline _: ImagePipeline) -> String? {
        guard let url = request.url else { return nil }
        return ImageLoadingService.cacheKey(for: url)
    }
}
