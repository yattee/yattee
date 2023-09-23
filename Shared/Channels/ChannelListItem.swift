import SwiftUI

struct ChannelListItem: View {
    var channel: Channel

    @Environment(\.inChannelView) private var inChannelView
    @Environment(\.inNavigationView) private var inNavigationView
    @Environment(\.navigationStyle) private var navigationStyle

    var body: some View {
        channelControl
            .contentShape(Rectangle())
    }

    @ViewBuilder private var channelControl: some View {
        if !channel.name.isEmpty {
            #if os(tvOS)
                channelButton
            #else
                if navigationStyle == .tab, inNavigationView {
                    channelNavigationLink
                } else {
                    channelButton
                }
            #endif
        }
    }

    @ViewBuilder private var channelNavigationLink: some View {
        NavigationLink(destination: ChannelVideosView(channel: channel)) {
            label
        }
    }

    @ViewBuilder private var channelButton: some View {
        Button {
            guard !inChannelView else { return }

            NavigationModel.shared.openChannel(
                channel,
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
        .help("\(channel.name) Channel")
    }

    @ViewBuilder private var displayAuthor: some View {
        if !channel.name.isEmpty {
            Text(channel.name)
                .fontWeight(.semibold)
        }
    }

    private var label: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack {
                ChannelAvatarView(channel: channel, subscribedBadge: false)
                    .id("channel-avatar-\(channel.id)")
                #if os(tvOS)
                    .frame(width: 90, height: 90)
                #else
                    .frame(width: 60, height: 60)
                #endif
            }
            .frame(width: thumbnailWidth)

            displayAuthor
                .multilineTextAlignment(.leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        #if os(tvOS)
            .frame(minHeight: 120)
        #else
            .frame(minHeight: 60)
        #endif
    }

    private var thumbnailWidth: Double {
        #if os(tvOS)
            250
        #else
            100
        #endif
    }
}

struct ChannelListItem_Previews: PreviewProvider {
    static var previews: some View {
        ChannelListItem(channel: Video.fixture.channel)
    }
}
