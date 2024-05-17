import Foundation
import Siesta

final class FavoriteResourceObserver: ObservableObject, ResourceObserver {
    @Published var contentItems = [ContentItem]()

    func resourceChanged(_ resource: Resource, event _: ResourceEvent) {
        // swiftlint:disable discouraged_optional_collection
        var newVideos: [Video]?
        var newItems: [ContentItem]?
        // swiftlint:enable discouraged_optional_collection

        var newChannel: Channel?
        var newChannelPlaylist: ChannelPlaylist?
        var newPlaylist: Playlist?
        var newPage: SearchPage?

        if let videos: [Video] = resource.typedContent() {
            newVideos = videos
        } else if let channel: Channel = resource.typedContent() {
            newChannel = channel
        } else if let playlist: ChannelPlaylist = resource.typedContent() {
            newChannelPlaylist = playlist
        } else if let playlist: Playlist = resource.typedContent() {
            newPlaylist = playlist
        } else if let page: SearchPage = resource.typedContent() {
            newPage = page
        } else if let items: [ContentItem] = resource.typedContent() {
            newItems = items
        }

        DispatchQueue.global(qos: .userInitiated).async {
            var newContentItems: [ContentItem] = []

            if let videos = newVideos {
                newContentItems = videos.map { ContentItem(video: $0) }
            } else if let channel = newChannel {
                newContentItems = channel.videos.map { ContentItem(video: $0) }
            } else if let playlist = newChannelPlaylist {
                newContentItems = playlist.videos.map { ContentItem(video: $0) }
            } else if let playlist = newPlaylist {
                newContentItems = playlist.videos.map { ContentItem(video: $0) }
            } else if let page = newPage {
                newContentItems = page.results
            } else if let items = newItems {
                newContentItems = items
            }

            DispatchQueue.main.async {
                if !newContentItems.isEmpty {
                    self.contentItems = newContentItems
                }
            }
        }
    }
}
