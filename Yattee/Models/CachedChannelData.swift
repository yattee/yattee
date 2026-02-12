//
//  CachedChannelData.swift
//  Yattee
//
//  Cached channel data from Subscription or RecentChannel for instant display.
//

import Foundation

/// Cached channel data loaded from local SwiftData stores (Subscription or RecentChannel).
/// Used to show channel info immediately while API responses are loading.
struct CachedChannelData: Codable {
    let name: String
    let thumbnailURL: URL?
    let bannerURL: URL?
    let subscriberCount: Int?

    /// In-memory cache of author data from video detail API responses.
    @MainActor
    private static var authorCache: [String: CachedChannelData] = [:]

    /// Whether the disk cache has been loaded into memory.
    @MainActor
    private static var diskLoaded = false

    /// Maximum number of cached author entries.
    private static let maxCacheSize = 500

    private static var cacheFileURL: URL {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        return caches.appendingPathComponent("AuthorCache", isDirectory: true)
            .appendingPathComponent("authors.json")
    }

    init(name: String, thumbnailURL: URL?, bannerURL: URL?, subscriberCount: Int?) {
        self.name = name
        self.thumbnailURL = thumbnailURL
        self.bannerURL = bannerURL
        self.subscriberCount = subscriberCount
    }

    @MainActor
    static func cacheAuthor(_ author: Author) {
        guard author.thumbnailURL != nil || author.subscriberCount != nil else { return }
        authorCache[author.id] = CachedChannelData(
            name: author.name,
            thumbnailURL: author.thumbnailURL,
            bannerURL: nil,
            subscriberCount: author.subscriberCount
        )

        // Evict oldest entries if over limit
        if authorCache.count > maxCacheSize {
            let excess = authorCache.count - maxCacheSize
            let keysToRemove = Array(authorCache.keys.prefix(excess))
            for key in keysToRemove {
                authorCache.removeValue(forKey: key)
            }
        }

        saveToDisk()
    }

    // MARK: - Disk Persistence

    @MainActor
    private static func loadFromDiskIfNeeded() {
        guard !diskLoaded else { return }
        diskLoaded = true

        let url = cacheFileURL
        guard FileManager.default.fileExists(atPath: url.path) else { return }

        do {
            let data = try Data(contentsOf: url)
            let decoded = try JSONDecoder().decode([String: CachedChannelData].self, from: data)
            // Only fill entries not already present in memory
            for (key, value) in decoded where authorCache[key] == nil {
                authorCache[key] = value
            }
        } catch {
            try? FileManager.default.removeItem(at: url)
        }
    }

    @MainActor
    private static func saveToDisk() {
        let snapshot = authorCache
        Task.detached(priority: .utility) {
            let url = cacheFileURL
            let directory = url.deletingLastPathComponent()
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            if let data = try? JSONEncoder().encode(snapshot) {
                try? data.write(to: url, options: .atomic)
            }
        }
    }

    init(from subscription: Subscription) {
        name = subscription.name
        thumbnailURL = subscription.avatarURL
        bannerURL = subscription.bannerURL
        subscriberCount = subscription.subscriberCount
    }

    init(from recentChannel: RecentChannel) {
        name = recentChannel.name
        thumbnailURL = recentChannel.thumbnailURLString.flatMap { URL(string: $0) }
        bannerURL = nil // RecentChannel doesn't store banner
        subscriberCount = recentChannel.subscriberCount
    }

    /// Load cached data for a channel ID from Subscription or RecentChannel.
    @MainActor
    static func load(for channelID: String, using dataManager: DataManager) -> CachedChannelData? {
        loadFromDiskIfNeeded()
        if let subscription = dataManager.subscription(for: channelID) {
            return CachedChannelData(from: subscription)
        }
        if let recentChannel = dataManager.recentChannelEntry(forChannelID: channelID) {
            return CachedChannelData(from: recentChannel)
        }
        // Finally, check in-memory cache from video detail API responses
        return authorCache[channelID]
    }
}

// MARK: - Author Enrichment

extension Author {
    /// Returns a new Author with missing fields filled in from cached channel data.
    func enriched(from cached: CachedChannelData) -> Author {
        Author(
            id: id,
            name: name,
            thumbnailURL: thumbnailURL ?? cached.thumbnailURL,
            subscriberCount: subscriberCount ?? cached.subscriberCount,
            instance: instance,
            url: url,
            hasRealChannelInfo: hasRealChannelInfo
        )
    }

    /// Convenience: looks up cached data for this author's ID and enriches if found.
    @MainActor
    func enriched(using dataManager: DataManager) -> Author {
        guard let cached = CachedChannelData.load(for: id, using: dataManager) else {
            return self
        }
        return enriched(from: cached)
    }
}
