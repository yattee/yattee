import Foundation
import SwiftUI

struct ContentItemView: View {
    let item: ContentItem

    var body: some View {
        Group {
            switch item.contentType {
            case .video:
                VideoCell(video: item.video)
            case .playlist:
                ChannelPlaylistCell(playlist: item.playlist)
            case .channel:
                ChannelCell(channel: item.channel)
            default:
                PlaceholderCell()
            }
        }
    }
}
