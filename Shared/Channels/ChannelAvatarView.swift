import SwiftUI

struct ChannelAvatarView: View {
    var channel: Channel?
    var video: Video?

    var subscribedBadge = true

    @ObservedObject private var accounts = AccountsModel.shared
    @ObservedObject private var subscribedChannels = SubscribedChannelsModel.shared

    @State private var url: URL?

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Group {
                Group {
                    if let url {
                        ThumbnailView(url: url)
                    } else {
                        ZStack {
                            Color(white: 0.6)
                                .opacity(0.5)

                            Group {
                                if let video, video.isLocal {
                                    Image(systemName: video.localStreamImageSystemName)
                                } else {
                                    Image(systemName: "play.rectangle")
                                }
                            }
                            .foregroundColor(.accentColor)
                            .font(.system(size: 20))
                            .contentShape(Rectangle())
                        }
                        .onAppear(perform: updateURL)
                    }
                }
                .clipShape(Circle())

                if subscribedBadge,
                   accounts.app.supportsSubscriptions,
                   accounts.signedIn,
                   let channel,
                   subscribedChannels.isSubscribing(channel.id)
                {
                    Image(systemName: "star.circle.fill")
                    #if os(tvOS)
                        .background(Color.black)
                    #else
                        .background(Color.background)
                    #endif
                        .clipShape(Circle())
                        .foregroundColor(.secondary)
                }
            }
        }
        .imageScale(.small)
    }

    func updateURL() {
        DispatchQueue.global(qos: .userInitiated).async {
            if let url = channel?.thumbnailURLOrCached {
                DispatchQueue.main.async {
                    self.url = url
                }
            }
        }
    }
}

struct ChannelAvatarView_Previews: PreviewProvider {
    static var previews: some View {
        ChannelAvatarView(channel: Video.fixture.channel)
    }
}
