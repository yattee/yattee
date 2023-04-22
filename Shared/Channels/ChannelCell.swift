import Foundation
import SDWebImageSwiftUI
import SwiftUI

struct ChannelCell: View {
    let channel: Channel

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
        NavigationLink(destination: ChannelVideosView(channel: channel)) {
            labelContent
        }
    }

    var button: some View {
        Button {
            NavigationModel.shared.openChannel(
                channel,
                navigationStyle: navigationStyle
            )
        } label: {
            labelContent
        }
        .buttonStyle(.plain)
    }

    var labelContent: some View {
        VStack {
            WebImage(url: channel.thumbnailURL, options: [.lowPriority])
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
