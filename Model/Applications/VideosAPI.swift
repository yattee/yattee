import AVFoundation
import Foundation
import Siesta

protocol VideosAPI {
    var account: Account! { get }
    var signedIn: Bool { get }

    func channel(_ id: String) -> Resource
    func channelVideos(_ id: String) -> Resource
    func trending(country: Country, category: TrendingCategory?) -> Resource
    func search(_ query: SearchQuery) -> Resource
    func searchSuggestions(query: String) -> Resource

    func video(_ id: Video.ID) -> Resource

    var subscriptions: Resource? { get }
    var feed: Resource? { get }
    var home: Resource? { get }
    var popular: Resource? { get }
    var playlists: Resource? { get }

    func subscribe(_ channelID: String, onCompletion: @escaping () -> Void)
    func unsubscribe(_ channelID: String, onCompletion: @escaping () -> Void)

    func playlist(_ id: String) -> Resource?
    func playlistVideo(_ playlistID: String, _ videoID: String) -> Resource?
    func playlistVideos(_ id: String) -> Resource?

    func channelPlaylist(_ id: String) -> Resource?

    func loadDetails(_ item: PlayerQueueItem, completionHandler: @escaping (PlayerQueueItem) -> Void)
    func shareURL(_ item: ContentItem, frontendHost: String?, time: CMTime?) -> URL?

    func comments(_ id: Video.ID, page: String?) -> Resource?
}

extension VideosAPI {
    func loadDetails(_ item: PlayerQueueItem, completionHandler: @escaping (PlayerQueueItem) -> Void = { _ in }) {
        guard (item.video?.streams ?? []).isEmpty else {
            completionHandler(item)
            return
        }

        video(item.videoID).load().onSuccess { response in
            guard let video: Video = response.typedContent() else {
                return
            }

            var newItem = item
            newItem.video = video

            completionHandler(newItem)
        }
    }

    func shareURL(_ item: ContentItem, frontendHost: String? = nil, time: CMTime? = nil) -> URL? {
        guard let frontendHost = frontendHost ?? account.instance.frontendHost else {
            return nil
        }

        var urlComponents = account.instance.urlComponents
        urlComponents.host = frontendHost

        var queryItems = [URLQueryItem]()

        switch item.contentType {
        case .video:
            urlComponents.path = "/watch"
            queryItems.append(.init(name: "v", value: item.video.videoID))
        case .channel:
            urlComponents.path = "/channel/\(item.channel.id)"
        case .playlist:
            urlComponents.path = "/playlist"
            queryItems.append(.init(name: "list", value: item.playlist.id))
        }

        if !time.isNil, time!.seconds.isFinite {
            queryItems.append(.init(name: "t", value: "\(Int(time!.seconds))s"))
        }

        if !queryItems.isEmpty {
            urlComponents.queryItems = queryItems
        }

        return urlComponents.url
    }
}
