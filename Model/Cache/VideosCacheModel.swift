import Cache
import Foundation
import Logging
import SwiftyJSON

struct VideosCacheModel: CacheModel {
    static let shared = Self()
    let logger = Logger(label: "stream.yattee.cache.videos")

    static let diskConfig = DiskConfig(name: "videos")
    static let memoryConfig = MemoryConfig()

    let storage = try? Storage<String, JSON>(
        diskConfig: Self.diskConfig,
        memoryConfig: Self.memoryConfig,
        fileManager: FileManager.default,
        transformer: BaseCacheModel.jsonTransformer
    )

    func storeVideo(_ video: Video) {
        logger.info("caching \(video.cacheKey)")
        try? storage?.setObject(video.json, forKey: video.cacheKey)

        ChannelsCacheModel.shared.storeIfMissing(video.channel)
    }

    func retrieveVideo(_ cacheKey: String) -> Video? {
        logger.debug("retrieving cache for \(cacheKey)")

        if let json = try? storage?.object(forKey: cacheKey) {
            return Video.from(json)
        }

        return nil
    }
}
