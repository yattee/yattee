import Cache
import Foundation
import Logging
import SwiftyJSON

struct ChannelPlaylistsCacheModel: CacheModel {
    static let shared = Self()
    let logger = Logger(label: "stream.yattee.cache.channel-playlists")

    static let diskConfig = DiskConfig(name: "channel-playlists")
    static let memoryConfig = MemoryConfig()

    var storage = try? Storage<String, JSON>(
        diskConfig: Self.diskConfig,
        memoryConfig: Self.memoryConfig,
        fileManager: FileManager.default,
        transformer: BaseCacheModel.jsonTransformer
    )

    func storePlaylist(playlist: ChannelPlaylist) {
        let date = iso8601DateFormatter.string(from: Date())
        logger.info("STORE \(playlist.cacheKey) -- \(date)")
        let feedTimeObject: JSON = ["date": date]
        let playlistObject: JSON = ["playlist": playlist.json.object]
        try? storage?.setObject(feedTimeObject, forKey: playlistTimeCacheKey(playlist.cacheKey))
        try? storage?.setObject(playlistObject, forKey: playlist.cacheKey)
    }

    func retrievePlaylist(_ playlist: ChannelPlaylist) -> ChannelPlaylist? {
        logger.info("RETRIEVE \(playlist.cacheKey)")

        if let json = try? storage?.object(forKey: playlist.cacheKey).dictionaryValue["playlist"] {
            return ChannelPlaylist.from(json)
        }

        return nil
    }

    func getPlaylistsTime(_ id: ChannelPlaylist.ID) -> Date? {
        if let json = try? storage?.object(forKey: playlistTimeCacheKey(id)),
           let string = json.dictionaryValue["date"]?.string,
           let date = iso8601DateFormatter.date(from: string)
        {
            return date
        }

        return nil
    }

    func getFormattedPlaylistTime(_ id: ChannelPlaylist.ID) -> String {
        getFormattedDate(getPlaylistsTime(id))
    }

    private func playlistTimeCacheKey(_ cacheKey: ChannelPlaylist.ID) -> String {
        "\(cacheKey)-time"
    }
}
