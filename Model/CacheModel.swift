import Cache
import Foundation
import SwiftyJSON

struct CacheModel {
    static var shared = CacheModel()

    var urlBookmarksStorage: Storage<String, Data>?
    var videoStorage: Storage<Video.ID, JSON>?

    init() {
        let urlBookmarksStorageConfig = DiskConfig(name: "URLBookmarks", expiry: .never)
        let urlBookmarksMemoryConfig = MemoryConfig(expiry: .never, countLimit: 100, totalCostLimit: 100)
        urlBookmarksStorage = try? Storage(diskConfig: urlBookmarksStorageConfig, memoryConfig: urlBookmarksMemoryConfig, transformer: TransformerFactory.forData())

        let videoStorageConfig = DiskConfig(name: "VideoStorage", expiry: .never)
        let videoStorageMemoryConfig = MemoryConfig(expiry: .never, countLimit: 100, totalCostLimit: 100)

        let toData: (JSON) throws -> Data = { try $0.rawData() }
        let fromData: (Data) throws -> JSON = { try JSON(data: $0) }

        let jsonTransformer = Transformer<JSON>(toData: toData, fromData: fromData)
        videoStorage = try? Storage<Video.ID, JSON>(diskConfig: videoStorageConfig, memoryConfig: videoStorageMemoryConfig, transformer: jsonTransformer)
    }
}
