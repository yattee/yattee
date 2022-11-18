import Defaults
import SwiftUI

struct VideoActions: View {
    @EnvironmentObject<AccountsModel> private var accounts
    @EnvironmentObject<NavigationModel> private var navigation
    @EnvironmentObject<SubscriptionsModel> private var subscriptions
    @EnvironmentObject<PlayerModel> private var player

    var video: Video?

    var body: some View {
        HStack {
            if let video {
                #if !os(tvOS)
                    if !video.isLocal || video.localStreamIsRemoteURL {
                        ShareButton(contentItem: .init(video: video)) {
                            actionButton("Share", systemImage: "square.and.arrow.up")
                        }

                        Spacer()
                    }
                #endif

                if !video.isLocal {
                    if accounts.signedIn, accounts.app.supportsUserPlaylists {
                        actionButton("Add", systemImage: "text.badge.plus") {
                            navigation.presentAddToPlaylist(video)
                        }
                        Spacer()
                    }
                    if accounts.signedIn, accounts.app.supportsSubscriptions {
                        if subscriptions.isSubscribing(video.channel.id) {
                            actionButton("Unsubscribe", systemImage: "xmark.circle") {
                                #if os(tvOS)
                                    subscriptions.unsubscribe(video.channel.id)
                                #else
                                    navigation.presentUnsubscribeAlert(video.channel, subscriptions: subscriptions)
                                #endif
                            }
                        } else {
                            actionButton("Subscribe", systemImage: "star.circle") {
                                subscriptions.subscribe(video.channel.id) {
                                    navigation.sidebarSectionChanged.toggle()
                                }
                            }
                        }
                        Spacer()
                    }
                }
            }

            if player.currentItem == nil {
                Spacer()
            }

            actionButton("Hide", systemImage: "chevron.down") {
                player.hide(animate: true)
            }

            if player.currentItem != nil {
                Spacer()
                actionButton("Close", systemImage: "xmark") {
                    player.closeCurrentItem()
                }
            }
        }
        .padding(.horizontal)
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .frame(height: 50)
        .borderBottom(height: 0.5, color: Color("ControlsBorderColor"))
        .foregroundColor(.accentColor)
    }

    func actionButton(
        _ name: String,
        systemImage: String,
        action: @escaping () -> Void = {}
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: systemImage)
                    .frame(width: 20, height: 20)
                Text(name)
                    .foregroundColor(.secondary)
                    .font(.caption2)
                    .allowsTightening(true)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(name))
    }
}

struct VideoActions_Previews: PreviewProvider {
    static var previews: some View {
        VideoActions()
            .injectFixtureEnvironmentObjects()
    }
}
