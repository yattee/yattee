import Cache
import Foundation
import Logging
import SwiftyJSON

struct VideosCacheModel {
    static let shared = VideosCacheModel()
    let logger = Logger(label: "stream.yattee.cache.videos")

    static let jsonToDataTransformer: (JSON) -> Data = { try! $0.rawData() }
    static let jsonFromDataTransformer: (Data) -> JSON = { try! JSON(data: $0) }
    static let jsonTransformer = Transformer(toData: jsonToDataTransformer, fromData: jsonFromDataTransformer)

    static let videosStorageDiskConfig = DiskConfig(name: "videos")
    static let vidoesStorageMemoryConfig = MemoryConfig()

    let videosStorage = try! Storage<String, JSON>(
        diskConfig: Self.videosStorageDiskConfig,
        memoryConfig: Self.vidoesStorageMemoryConfig,
        transformer: Self.jsonTransformer
    )

    func storeVideo(_ video: Video) {
        logger.info("caching \(video.cacheKey)")
        try? videosStorage.setObject(video.json, forKey: video.cacheKey)
    }

    func retrieveVideo(_ cacheKey: String) -> Video? {
        logger.info("retrieving cache for \(cacheKey)")

        if let json = try? videosStorage.object(forKey: cacheKey) {
            return Video.from(json)
        }

        return nil
    }
}
