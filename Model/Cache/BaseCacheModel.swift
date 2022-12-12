import Cache
import Foundation
import Logging
import SwiftyJSON

struct BaseCacheModel {
    static var shared = BaseCacheModel()

    static let jsonToDataTransformer: (JSON) -> Data = { try! $0.rawData() }
    static let jsonFromDataTransformer: (Data) -> JSON = { try! JSON(data: $0) }
    static let jsonTransformer = Transformer(toData: jsonToDataTransformer, fromData: jsonFromDataTransformer)

    var models: [CacheModel] {
        [
            FeedCacheModel.shared,
            VideosCacheModel.shared,
            PlaylistsCacheModel.shared,
            ChannelPlaylistsCacheModel.shared,
            SubscribedChannelsModel.shared
        ]
    }

    func clear() {
        models.forEach { $0.clear() }
    }

    var totalSize: Int {
        models.compactMap { $0.storage?.totalDiskStorageSize }.reduce(0, +)
    }

    var totalSizeFormatted: String {
        byteCountFormatter.string(fromByteCount: Int64(totalSize))
    }

    private var byteCountFormatter: ByteCountFormatter { .init() }
}
