import Foundation
import Siesta

protocol VideosAPI {
    var account: Account! { get }
    var signedIn: Bool { get }

    func channel(_ id: String) -> Resource
    func trending(country: Country, category: TrendingCategory?) -> Resource
    func search(_ query: SearchQuery) -> Resource
    func searchSuggestions(query: String) -> Resource

    func video(_ id: Video.ID) -> Resource

    var subscriptions: Resource? { get }
    var feed: Resource? { get }
    var home: Resource? { get }
    var popular: Resource? { get }
    var playlists: Resource? { get }

    func channelSubscription(_ id: String) -> Resource?

    func playlistVideo(_ playlistID: String, _ videoID: String) -> Resource?
    func playlistVideos(_ id: String) -> Resource?

    func channelPlaylist(_ id: String) -> Resource?

    func loadDetails(_ item: PlayerQueueItem, completionHandler: @escaping (PlayerQueueItem) -> Void)
    func shareURL(_ item: ContentItem) -> URL
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

    func shareURL(_ item: ContentItem) -> URL {
        var urlComponents = account.instance.urlComponents
        urlComponents.host = account.instance.frontendHost
        switch item.contentType {
        case .video:
            urlComponents.path = "/watch"
            urlComponents.query = "v=\(item.video.videoID)"
        case .channel:
            urlComponents.path = "/channel/\(item.channel.id)"
        case .playlist:
            urlComponents.path = "/playlist"
            urlComponents.query = "list=\(item.playlist.id)"
        }

        return urlComponents.url!
    }
}
