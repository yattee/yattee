import Foundation
import Siesta

final class FavoriteResourceObserver: ObservableObject, ResourceObserver {
    @Published var videos = [Video]()

    func resourceChanged(_ resource: Resource, event _: ResourceEvent) {
        if let videos: [Video] = resource.typedContent() {
            self.videos = videos
        } else if let channel: Channel = resource.typedContent() {
            videos = channel.videos
        } else if let playlist: ChannelPlaylist = resource.typedContent() {
            videos = playlist.videos
        } else if let playlist: Playlist = resource.typedContent() {
            videos = playlist.videos
        }
    }

    var contentItems: [ContentItem] {
        videos.map { ContentItem(video: $0) }
    }
}
