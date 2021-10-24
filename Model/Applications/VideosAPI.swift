import Foundation
import Siesta

protocol VideosAPI {
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
}
