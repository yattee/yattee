import Cache
import Foundation
import Logging
import SwiftyJSON

struct CacheModel {
    static var shared = CacheModel()

    static let jsonToDataTransformer: (JSON) -> Data = { try! $0.rawData() }
    static let jsonFromDataTransformer: (Data) -> JSON = { try! JSON(data: $0) }
    static let jsonTransformer = Transformer(toData: jsonToDataTransformer, fromData: jsonFromDataTransformer)

    func clear() {
        FeedCacheModel.shared.clear()
        VideosCacheModel.shared.clear()
    }

    var totalSize: Int {
        (FeedCacheModel.shared.storage.totalDiskStorageSize ?? 0) +
            (VideosCacheModel.shared.storage.totalDiskStorageSize ?? 0)
    }

    var totalSizeFormatted: String {
        totalSizeFormatter.string(fromByteCount: Int64(totalSize))
    }

    private var totalSizeFormatter: ByteCountFormatter {
        .init()
    }
}
