import Foundation
import Siesta

final class FavoriteResourceObserver: ObservableObject, ResourceObserver {
    @Published var contentItems = [ContentItem]()

    func resourceChanged(_ resource: Resource, event _: ResourceEvent) {
        if let videos: [Video] = resource.typedContent() {
            contentItems = videos.map { ContentItem(video: $0) }
        } else if let channel: Channel = resource.typedContent() {
            contentItems = channel.videos.map { ContentItem(video: $0) }
        } else if let playlist: ChannelPlaylist = resource.typedContent() {
            contentItems = playlist.videos.map { ContentItem(video: $0) }
        } else if let playlist: Playlist = resource.typedContent() {
            contentItems = playlist.videos.map { ContentItem(video: $0) }
        } else if let items: [ContentItem] = resource.typedContent() {
            contentItems = items
        }
    }
}
