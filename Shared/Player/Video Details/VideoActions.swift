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
                ShareButton(contentItem: .init(video: video)) {
                    actionButton("Share", systemImage: "square.and.arrow.up")
                }

                Spacer()

                actionButton("Add", systemImage: "text.badge.plus") {
                    navigation.presentAddToPlaylist(video)
                }
                if accounts.app.supportsSubscriptions, accounts.signedIn {
                    Spacer()
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
                }
            }
            Spacer()

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
        .borderBottom(height: 0.4, color: Color("ControlsBorderColor"))
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .frame(height: 50)
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
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(name))
    }

    @ViewBuilder var videoProperties: some View {
        HStack(spacing: 2) {
            publishedDateSection

            Spacer()

            HStack(spacing: 4) {
                Image(systemName: "eye")

                if let views = video?.viewsCount, player.videoBeingOpened.isNil {
                    Text(views)
                } else {
                    Text("1,234M").redacted(reason: .placeholder)
                }

                Image(systemName: "hand.thumbsup")

                if let likes = video?.likesCount, player.videoBeingOpened.isNil {
                    Text(likes)
                } else {
                    Text("1,234M").redacted(reason: .placeholder)
                }

                if Defaults[.enableReturnYouTubeDislike] {
                    Image(systemName: "hand.thumbsdown")

                    if let dislikes = video?.dislikesCount, player.videoBeingOpened.isNil {
                        Text(dislikes)
                    } else {
                        Text("1,234M").redacted(reason: .placeholder)
                    }
                }
            }
        }
        .font(.system(size: 12))
        .foregroundColor(.secondary)
    }

    var publishedDateSection: some View {
        Group {
            if let video {
                HStack(spacing: 4) {
                    if let published = video.publishedDate {
                        Text(published)
                    } else {
                        Text("1 century ago").redacted(reason: .placeholder)
                    }
                }
            }
        }
    }
}

struct VideoActions_Previews: PreviewProvider {
    static var previews: some View {
        VideoActions()
            .injectFixtureEnvironmentObjects()
    }
}
