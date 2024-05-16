import SDWebImageSwiftUI
import SwiftUI

struct ChannelPlaylistCell: View {
    let playlist: ChannelPlaylist

    @Environment(\.navigationStyle) private var navigationStyle

    var body: some View {
        #if os(tvOS)
            button
        #else
            if navigationStyle == .tab {
                navigationLink
            } else {
                button
            }
        #endif
    }

    var navigationLink: some View {
        NavigationLink(destination: ChannelPlaylistView(playlist: playlist)) { cell }
    }

    var button: some View {
        Button {
            NavigationModel.shared.openChannelPlaylist(playlist, navigationStyle: navigationStyle)
        } label: {
            cell
        }
        .buttonStyle(.plain)
    }

    var cell: some View {
        content
            .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
            .contentShape(RoundedRectangle(cornerRadius: 12))
    }

    var content: some View {
        VStack {
            WebImage(url: playlist.thumbnailURL, options: [.lowPriority])
                .resizable()
                .placeholder {
                    Rectangle().fill(Color("PlaceholderColor"))
                }
                .indicator(.activity)
                .frame(width: 165, height: 88)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            Group {
                DetailBadge(text: playlist.title, style: .prominent)
                    .lineLimit(2)

                Text("\(playlist.videosCount ?? playlist.videos.count) videos")
                    .foregroundColor(.secondary)
                    .frame(height: 20)
            }
        }
    }
}

struct ChannelPlaylistCell_Previews: PreviewProvider {
    static var previews: some View {
        ChannelPlaylistCell(playlist: ChannelPlaylist.fixture)
            .frame(maxWidth: 320)
            .injectFixtureEnvironmentObjects()
    }
}
