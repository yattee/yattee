import SDWebImageSwiftUI
import SwiftUI

struct ChannelPlaylistCell: View {
    let playlist: ChannelPlaylist

    @Environment(\.navigationStyle) private var navigationStyle

    var navigation = NavigationModel.shared

    var body: some View {
        if navigationStyle == .tab {
            NavigationLink(destination: ChannelPlaylistView(playlist: playlist)) { cell }
        } else {
            Button {
                NavigationModel.shared.openChannelPlaylist(playlist, navigationStyle: navigationStyle)
            } label: {
                cell
            }
            .buttonStyle(.plain)
        }
    }

    var cell: some View {
        content
            .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
            .contentShape(RoundedRectangle(cornerRadius: 12))
    }

    var content: some View {
        VStack {
            HStack(alignment: .top, spacing: 3) {
                Image(systemName: "list.and.film")
                Text("Playlist".localized().uppercased())
                    .fontWeight(.light)
                    .opacity(0.6)
            }
            .foregroundColor(.secondary)

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
