import SwiftUI

struct ChannelPlaylistListItem: View {
    var playlist: ChannelPlaylist

    @Environment(\.inNavigationView) private var inNavigationView
    @Environment(\.navigationStyle) private var navigationStyle

    var body: some View {
        playlistControl
            .contentShape(Rectangle())
    }

    var thumbnailView: some View {
        ThumbnailView(url: playlist.thumbnailURL)
        #if os(tvOS)
            .frame(width: 250, height: 140)
        #else
            .frame(width: 100, height: 60)
        #endif
            .clipShape(RoundedRectangle(cornerRadius: 2))
    }

    @ViewBuilder private var playlistControl: some View {
        #if os(tvOS)
            playlistButton
        #else
            if navigationStyle == .tab, inNavigationView {
                playlistNavigationLink
            } else {
                playlistButton
            }
        #endif
    }

    @ViewBuilder private var playlistNavigationLink: some View {
        NavigationLink(destination: ChannelPlaylistView(playlist: playlist)) {
            label
        }
    }

    @ViewBuilder private var playlistButton: some View {
        Button {
            NavigationModel.shared.openChannelPlaylist(
                playlist,
                navigationStyle: navigationStyle
            )
        } label: {
            label
        }
        #if os(tvOS)
        .buttonStyle(.card)
        #else
        .buttonStyle(.plain)
        #endif
        .help("\(playlist.title) playlist")
    }

    @ViewBuilder private var displayTitle: some View {
        Text(playlist.title)
            .fontWeight(.semibold)
    }

    private var label: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack {
                thumbnailView
            }
            .frame(width: thumbnailWidth)
            #if os(tvOS)
                .frame(minHeight: 100)
            #else
                .frame(minHeight: 60)
            #endif

            VStack(alignment: .leading) {
                displayTitle
                Text("\(playlist.videosCount ?? playlist.videos.count) videos")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .multilineTextAlignment(.leading)
        }
        #if os(tvOS)
        .padding(.vertical)
        #endif
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var thumbnailWidth: Double {
        #if os(tvOS)
            250
        #else
            100
        #endif
    }
}

struct ChannelPlaylistListItem_Previews: PreviewProvider {
    static var previews: some View {
        ChannelPlaylistListItem(playlist: ChannelPlaylist.fixture)
    }
}
