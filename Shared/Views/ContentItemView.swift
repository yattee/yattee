import Defaults
import Foundation
import SwiftUI

struct ContentItemView: View {
    let item: ContentItem
    @Environment(\.listingStyle) private var listingStyle
    @Environment(\.noListingDividers) private var noListingDividers
    @Default(.hideShorts) private var hideShorts
    @Default(.hideWatched) private var hideWatched

    @FetchRequest private var watchRequest: FetchedResults<Watch>

    init(item: ContentItem) {
        self.item = item
        // Only create FetchRequest for video items, not for all items
        if item.contentType == .video, let videoID = item.video?.videoID {
            let predicate = NSPredicate(format: "videoID = %@", videoID as CVarArg)
            _watchRequest = FetchRequest<Watch>(
                sortDescriptors: [],
                predicate: predicate,
                animation: .default
            )
        } else {
            // Empty fetch request for non-video items
            _watchRequest = FetchRequest<Watch>(
                sortDescriptors: [],
                predicate: NSPredicate(value: false),
                animation: .default
            )
        }
    }

    @ViewBuilder var body: some View {
        if itemVisible {
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
    }

    var itemVisible: Bool {
        if hideWatched, watch?.finished ?? false {
            return false
        }

        guard FeatureFlags.hideShortsEnabled, hideShorts, item.contentType == .video, let video = item.video else {
            return true
        }

        return !video.short
    }

    @ViewBuilder func videoItem(_ video: Video) -> some View {
        if listingStyle == .cells {
            VideoCell(video: video, watch: watch)
        } else {
            let item = PlayerQueueItem(video)
            PlayerQueueRow(item: item, watch: watch)
                .contextMenu {
                    VideoContextMenuView(video: video)
                }
                .id(item.contentItem.cacheKey)
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

    private var watch: Watch? {
        watchRequest.first
    }
}
