import SDWebImageSwiftUI
import SwiftUI

struct ChannelPlaylistCell: View {
    let playlist: ChannelPlaylist

    @Environment(\.navigationStyle) private var navigationStyle

    @EnvironmentObject<NavigationModel> private var navigation
    @EnvironmentObject<RecentsModel> private var recents

    var body: some View {
        Button {
            let recent = RecentItem(from: playlist)
            recents.add(recent)
            navigation.presentingPlaylist = true

            if navigationStyle == .sidebar {
                navigation.sidebarSectionChanged.toggle()
                navigation.tabSelection = .recentlyOpened(recent.tag)
            }
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
                Text("Playlist".uppercased())
                    .fontWeight(.light)
                    .opacity(0.6)
            }
            .foregroundColor(.secondary)

            if #available(iOS 15, macOS 12, *) {
                AsyncImage(url:  playlist.thumbnailURL) { image in
                    image
                        .resizable()
                } placeholder: {
                    Rectangle().foregroundColor(Color("PlaceholderColor"))
                }
            } else {
                WebImage(url: playlist.thumbnailURL)
                    .resizable()
                    .placeholder {
                        Rectangle().fill(Color("PlaceholderColor"))
                    }
                    .indicator(.activity)
                    .frame(width: 165, height: 88)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
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
