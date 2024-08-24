import Cache
import Foundation
import Logging
import SwiftyJSON

struct ChannelsCacheModel: CacheModel {
    static let shared = Self()
    let logger = Logger(label: "stream.yattee.cache.channels")

    static let diskConfig = DiskConfig(name: "channels")
    static let memoryConfig = MemoryConfig()

    let storage = try? Storage<String, JSON>(
        diskConfig: Self.diskConfig,
        memoryConfig: Self.memoryConfig,
        fileManager: FileManager.default,
        transformer: BaseCacheModel.jsonTransformer
    )

    func store(_ channel: Channel) {
        guard channel.hasExtendedDetails else {
            logger.debug("not caching \(channel.cacheKey)")
            return
        }

        logger.info("caching \(channel.cacheKey)")
        try? storage?.setObject(channel.json, forKey: channel.cacheKey)
    }

    func storeIfMissing(_ channel: Channel) {
        guard let storage, !storage.objectExists(forKey: channel.cacheKey) else {
            return
        }

        store(channel)
    }

    func retrieve(_ cacheKey: String) -> ChannelPage? {
        logger.debug("retrieving cache for \(cacheKey)")

        if let json = try? storage?.object(forKey: cacheKey) {
            return ChannelPage(channel: Channel.from(json))
        }

        return nil
    }
}
