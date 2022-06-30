import Foundation
import SDWebImageSwiftUI
import SwiftUI

struct ChannelCell: View {
    let channel: Channel

    @Environment(\.navigationStyle) private var navigationStyle

    @EnvironmentObject<NavigationModel> private var navigation
    @EnvironmentObject<PlayerModel> private var player
    @EnvironmentObject<RecentsModel> private var recents

    var body: some View {
        Button {
            NavigationModel.openChannel(
                channel,
                player: player,
                recents: recents,
                navigation: navigation,
                navigationStyle: navigationStyle
            )
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
                Image(systemName: "person.crop.rectangle")
                Text("Channel".uppercased())
                    .fontWeight(.light)
                    .opacity(0.6)
            }
            .foregroundColor(.secondary)

            WebImage(url: channel.thumbnailURL)
                .resizable()
                .placeholder {
                    Rectangle().fill(Color("PlaceholderColor"))
                }
                .indicator(.activity)
                .frame(width: 88, height: 88)
                .clipShape(Circle())

            DetailBadge(text: channel.name, style: .prominent)

            Group {
                if let subscriptions = channel.subscriptionsString {
                    Text("\(subscriptions) subscribers")
                        .foregroundColor(.secondary)
                } else {
                    Text("")
                }
            }
            .frame(height: 20)
        }
    }
}

struct ChannelSearchItem_Preview: PreviewProvider {
    static var previews: some View {
        Group {
            ChannelCell(channel: Video.fixture.channel)
        }
        .frame(maxWidth: 300, maxHeight: 200)
        .injectFixtureEnvironmentObjects()
    }
}
