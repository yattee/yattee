import Cache
import Foundation
import Logging
import SwiftyJSON

struct VideosCacheModel: CacheModel {
    static let shared = VideosCacheModel()
    let logger = Logger(label: "stream.yattee.cache.videos")

    static let diskConfig = DiskConfig(name: "videos")
    static let memoryConfig = MemoryConfig()

    let storage = try? Storage<String, JSON>(
        diskConfig: Self.diskConfig,
        memoryConfig: Self.memoryConfig,
        transformer: BaseCacheModel.jsonTransformer
    )

    func storeVideo(_ video: Video) {
        logger.info("caching \(video.cacheKey)")
        try? storage?.setObject(video.json, forKey: video.cacheKey)
    }

    func retrieveVideo(_ cacheKey: String) -> Video? {
        logger.info("retrieving cache for \(cacheKey)")

        if let json = try? storage?.object(forKey: cacheKey) {
            return Video.from(json)
        }

        return nil
    }
}
