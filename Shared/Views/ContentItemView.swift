import Foundation
import SwiftUI

struct ContentItemView: View {
    let item: ContentItem
    @Environment(\.listingStyle) private var listingStyle

    var body: some View {
        Group {
            switch item.contentType {
            case .video:
                if listingStyle == .cells {
                    VideoCell(video: item.video)
                } else {
                    PlayerQueueRow(item: .init(item.video))
                        .contextMenu {
                            VideoContextMenuView(video: item.video)
                        }
                    #if os(tvOS)
                        .padding(.horizontal, 30)
                    #endif

                    #if !os(tvOS)
                        Divider()
                    #endif
                }
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
