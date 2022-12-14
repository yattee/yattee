import Foundation
import SwiftUI

struct ChannelLinkView<ChannelLabel: View>: View {
    let channel: Channel
    let channelLabel: ChannelLabel

    @Environment(\.inChannelView) private var inChannelView
    @Environment(\.inNavigationView) private var inNavigationView
    @Environment(\.navigationStyle) private var navigationStyle

    init(
        channel: Channel,
        @ViewBuilder channelLabel: () -> ChannelLabel
    ) {
        self.channel = channel
        self.channelLabel = channelLabel()
    }

    var body: some View {
        channelControl
    }

    @ViewBuilder private var channelControl: some View {
        if !channel.name.isEmpty {
            #if os(tvOS)
                channelLabel
            #else
                if navigationStyle == .tab, inNavigationView {
                    channelNavigationLink
                } else {
                    channelButton
                    #if os(macOS)
                    .onHover(perform: onHover(_:))
                    #endif
                }
            #endif
        }
    }

    @ViewBuilder private var channelNavigationLink: some View {
        NavigationLink(destination: ChannelVideosView(channel: channel)) {
            channelLabel
        }
    }

    @ViewBuilder private var channelButton: some View {
        Button {
            guard !inChannelView else {
                return
            }

            NavigationModel.shared.openChannel(
                channel,
                navigationStyle: navigationStyle
            )
        } label: {
            channelLabel
        }
        #if os(tvOS)
        .buttonStyle(.card)
        #else
        .buttonStyle(.plain)
        #endif
        .help("\(channel.name) Channel")
    }

    #if os(macOS)
        private func onHover(_ inside: Bool) {
            if inside {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
    #endif
}
