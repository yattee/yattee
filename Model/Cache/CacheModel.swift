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
        PlaylistsCacheModel.shared.clear()
    }

    var totalSize: Int {
        (FeedCacheModel.shared.storage.totalDiskStorageSize ?? 0) +
            (VideosCacheModel.shared.storage.totalDiskStorageSize ?? 0) +
            (PlaylistsCacheModel.shared.storage.totalDiskStorageSize ?? 0)
    }

    var totalSizeFormatted: String {
        byteCountFormatter.string(fromByteCount: Int64(totalSize))
    }

    var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .medium

        return formatter
    }

    var dateFormatterForTimeOnly: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .medium

        return formatter
    }

    var iso8601DateFormatter: ISO8601DateFormatter { .init() }

    private var byteCountFormatter: ByteCountFormatter { .init() }
}
