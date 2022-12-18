import Foundation
import SwiftUI

struct ContentItemView: View {
    let item: ContentItem
    @Environment(\.listingStyle) private var listingStyle
    @Environment(\.noListingDividers) private var noListingDividers

    var body: some View {
        Group {
            switch item.contentType {
            case .video:
                videoItem(item.video)
            case .channel:
                channelItem(item.channel)
            case .playlist:
                playlistItem(item.playlist)
            default:
                placeholderItem()
            }
        }
        .id(item.cacheKey)
    }

    @ViewBuilder func videoItem(_ video: Video) -> some View {
        if listingStyle == .cells {
            VideoCell(video: video)
        } else {
            let item = PlayerQueueItem(video)
            PlayerQueueRow(item: item)
                .contextMenu {
                    VideoContextMenuView(video: video)
                }
                .id(item.id)
            #if os(tvOS)
                .padding(.horizontal, 30)
            #endif

            #if !os(tvOS)
                Divider()
                    .opacity(noListingDividers ? 0 : 1)
            #endif
        }
    }

    @ViewBuilder func playlistItem(_ playlist: ChannelPlaylist) -> some View {
        if listingStyle == .cells {
            ChannelPlaylistCell(playlist: playlist)
        } else {
            ChannelPlaylistListItem(playlist: playlist)
            #if os(tvOS)
                .padding(.horizontal, 30)
            #endif

            #if !os(tvOS)
                Divider()
            #endif
        }
    }

    @ViewBuilder func channelItem(_ channel: Channel) -> some View {
        if listingStyle == .cells {
            ChannelCell(channel: channel)
        } else {
            ChannelListItem(channel: channel)
            #if os(tvOS)
                .padding(.horizontal, 30)
            #endif

            #if !os(tvOS)
                Divider()
            #endif
        }
    }

    @ViewBuilder func placeholderItem() -> some View {
        if listingStyle == .cells {
            PlaceholderCell()
                .id(item.id)
        } else {
            PlaceholderListItem()
            #if os(tvOS)
                .padding(.horizontal, 30)
            #endif

            #if !os(tvOS)
                Divider()
            #endif
        }
    }
}
