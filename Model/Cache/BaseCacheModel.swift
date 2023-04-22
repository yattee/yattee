import Cache
import Foundation
import Logging
import SwiftyJSON

struct BaseCacheModel {
    static var shared = Self()

    static let jsonToDataTransformer: (JSON) -> Data = { try! $0.rawData() }
    static let jsonFromDataTransformer: (Data) -> JSON = { try! JSON(data: $0) }
    static let jsonTransformer = Transformer(toData: jsonToDataTransformer, fromData: jsonFromDataTransformer)

    static let imageCache = URLCache(memoryCapacity: 512 * 1000 * 1000, diskCapacity: 10 * 1000 * 1000 * 1000)

    var models: [CacheModel] {
        [
            FeedCacheModel.shared,
            VideosCacheModel.shared,
            ChannelsCacheModel.shared,
            PlaylistsCacheModel.shared,
            ChannelPlaylistsCacheModel.shared,
            SubscribedChannelsModel.shared
        ]
    }

    func clear() {
        models.forEach { $0.clear() }

        Self.imageCache.removeAllCachedResponses()
    }

    var totalSize: Int {
        models.compactMap { $0.storage?.totalDiskStorageSize }.reduce(0, +) + Self.imageCache.currentDiskUsage
    }

    var totalSizeFormatted: String {
        byteCountFormatter.string(fromByteCount: Int64(totalSize))
    }

    private var byteCountFormatter: ByteCountFormatter { .init() }
}
