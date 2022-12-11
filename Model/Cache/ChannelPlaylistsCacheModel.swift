import Cache
import Foundation
import Logging
import SwiftyJSON

struct ChannelPlaylistsCacheModel {
    static let shared = ChannelPlaylistsCacheModel()
    let logger = Logger(label: "stream.yattee.cache.channel-playlists")

    static let diskConfig = DiskConfig(name: "channel-playlists")
    static let memoryConfig = MemoryConfig()

    let storage = try! Storage<String, JSON>(
        diskConfig: Self.diskConfig,
        memoryConfig: Self.memoryConfig,
        transformer: CacheModel.jsonTransformer
    )

    func storePlaylist(playlist: ChannelPlaylist) {
        let date = CacheModel.shared.iso8601DateFormatter.string(from: Date())
        logger.info("STORE \(playlistCacheKey(playlist.id)) -- \(date)")
        let feedTimeObject: JSON = ["date": date]
        let playlistObject: JSON = ["playlist": playlist.json.object]
        try? storage.setObject(feedTimeObject, forKey: playlistTimeCacheKey(playlist.id))
        try? storage.setObject(playlistObject, forKey: playlistCacheKey(playlist.id))
    }

    func retrievePlaylist(_ id: ChannelPlaylist.ID) -> ChannelPlaylist? {
        logger.info("RETRIEVE \(playlistCacheKey(id))")

        if let json = try? storage.object(forKey: playlistCacheKey(id)).dictionaryValue["playlist"] {
            return ChannelPlaylist.from(json)
        }

        return nil
    }

    func getPlaylistsTime(_ id: ChannelPlaylist.ID) -> Date? {
        if let json = try? storage.object(forKey: playlistTimeCacheKey(id)),
           let string = json.dictionaryValue["date"]?.string,
           let date = CacheModel.shared.iso8601DateFormatter.date(from: string)
        {
            return date
        }

        return nil
    }

    func getFormattedPlaylistTime(_ id: ChannelPlaylist.ID) -> String {
        if let time = getPlaylistsTime(id) {
            let isSameDay = Calendar(identifier: .iso8601).isDate(time, inSameDayAs: Date())
            let formatter = isSameDay ? CacheModel.shared.dateFormatterForTimeOnly : CacheModel.shared.dateFormatter
            return formatter.string(from: time)
        }

        return ""
    }

    func clear() {
        try? storage.removeAll()
    }

    private func playlistCacheKey(_ playlist: ChannelPlaylist.ID) -> String {
        "channelplaylists-\(playlist)"
    }

    private func playlistTimeCacheKey(_ playlist: ChannelPlaylist.ID) -> String {
        "\(playlistCacheKey(playlist))-time"
    }
}
