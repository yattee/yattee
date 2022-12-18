import Defaults
import SwiftUI

struct VideoActions: View {
    @ObservedObject private var accounts = AccountsModel.shared
    var navigation = NavigationModel.shared
    @ObservedObject private var subscriptions = SubscribedChannelsModel.shared
    @ObservedObject private var player = PlayerModel.shared

    var video: Video?

    @Default(.playerActionsButtonLabelStyle) private var playerActionsButtonLabelStyle

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

            actionButton("Hide", systemImage: "chevron.down") {
                player.hide(animate: true)
            }

            Spacer()
            actionButton("Close", systemImage: "xmark") {
//                TODO: setting
//                    player.pause()
//                    WatchNextViewModel.shared.prepareForEmptyPlayerPlaceholder(player.currentItem)
//                    WatchNextViewModel.shared.open()
                player.closeCurrentItem()
            }
            .disabled(player.currentItem == nil)
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
                if playerActionsButtonLabelStyle.text {
                    Text(name.localized())
                        .foregroundColor(.secondary)
                        .font(.caption2)
                        .allowsTightening(true)
                }
            }
            .padding(.horizontal, playerActionsButtonLabelStyle.text ? 6 : 12)
            .padding(.vertical, playerActionsButtonLabelStyle.text ? 5 : 10)
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
