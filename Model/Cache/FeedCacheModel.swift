import Cache
import Defaults
import Foundation
import Logging
import SwiftyJSON

struct FeedCacheModel: CacheModel {
    static let shared = Self()
    let logger = Logger(label: "stream.yattee.cache.feed")

    static let diskConfig = DiskConfig(name: "feed")
    static let memoryConfig = MemoryConfig()

    let storage = try? Storage<String, JSON>(
        diskConfig: Self.diskConfig,
        memoryConfig: Self.memoryConfig,
        fileManager: FileManager.default,
        transformer: BaseCacheModel.jsonTransformer
    )

    func storeFeed(account: Account, videos: [Video]) {
        DispatchQueue.global(qos: .background).async {
            let date = iso8601DateFormatter.string(from: Date())
            logger.info("caching feed \(account.feedCacheKey) -- \(date)")
            let feedTimeObject: JSON = ["date": date]
            let videosObject: JSON = ["videos": videos.prefix(cacheLimit).map(\.json.object)]
            try? storage?.setObject(feedTimeObject, forKey: feedTimeCacheKey(account.feedCacheKey))
            try? storage?.setObject(videosObject, forKey: account.feedCacheKey)
        }
    }

    func retrieveFeed(account: Account) -> [Video] {
        logger.debug("retrieving cache for \(account.feedCacheKey)")

        if let json = try? storage?.object(forKey: account.feedCacheKey),
           let videos = json.dictionaryValue["videos"]
        {
            return videos.arrayValue.map { Video.from($0) }
        }

        return []
    }

    func getFeedTime(account: Account) -> Date? {
        if let json = try? storage?.object(forKey: feedTimeCacheKey(account.feedCacheKey)),
           let string = json.dictionaryValue["date"]?.string,
           let date = iso8601DateFormatter.date(from: string)
        {
            return date
        }

        return nil
    }

    private var cacheLimit: Int {
        let setting = Int(Defaults[.feedCacheSize]) ?? 0
        if setting > 0 {
            return setting
        }

        return 50
    }

    private func feedTimeCacheKey(_ feedCacheKey: String) -> String {
        "\(feedCacheKey)-feedTime"
    }
}
