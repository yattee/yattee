import SDWebImageSwiftUI
import SwiftUI

struct ChannelPlaylistCell: View {
    let playlist: ChannelPlaylist

    @Environment(\.navigationStyle) private var navigationStyle

    var navigation = NavigationModel.shared

    var body: some View {
        Button {
            NavigationModel.shared.openChannelPlaylist(playlist, navigationStyle: navigationStyle)
        } label: {
            content
                .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
                .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
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
