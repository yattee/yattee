import Defaults
import SwiftUI

struct VideoActions: View {
    enum Action: String, CaseIterable {
        case share
        case addToPlaylist
        case subscribe
        case settings
        case next
        case hide
        case close
    }

    @ObservedObject private var accounts = AccountsModel.shared
    var navigation = NavigationModel.shared
    @ObservedObject private var subscriptions = SubscribedChannelsModel.shared
    @ObservedObject private var player = PlayerModel.shared

    var video: Video?

    @Default(.openWatchNextOnClose) private var openWatchNextOnClose
    @Default(.playerActionsButtonLabelStyle) private var playerActionsButtonLabelStyle

    @Default(.actionButtonShareEnabled) private var actionButtonShareEnabled
    @Default(.actionButtonAddToPlaylistEnabled) private var actionButtonAddToPlaylistEnabled
    @Default(.actionButtonSubscribeEnabled) private var actionButtonSubscribeEnabled
    @Default(.actionButtonSettingsEnabled) private var actionButtonSettingsEnabled
    @Default(.actionButtonNextEnabled) private var actionButtonNextEnabled
    @Default(.actionButtonHideEnabled) private var actionButtonHideEnabled
    @Default(.actionButtonCloseEnabled) private var actionButtonCloseEnabled
    @Default(.actionButtonNextQueueCountEnabled) private var actionButtonNextQueueCountEnabled

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Action.allCases, id: \.self) { action in
                actionBody(action)
                    .frame(maxWidth: .infinity)
            }
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .frame(height: 50)
        .borderBottom(height: 0.5, color: Color("ControlsBorderColor"))
        .foregroundColor(.accentColor)
    }

    func isVisible(_ action: Action) -> Bool {
        switch action {
        case .share:
            return actionButtonShareEnabled
        case .addToPlaylist:
            return actionButtonAddToPlaylistEnabled
        case .subscribe:
            return actionButtonSubscribeEnabled
        case .settings:
            return actionButtonSettingsEnabled
        case .next:
            return actionButtonNextEnabled
        case .hide:
            return actionButtonHideEnabled
        case .close:
            return actionButtonCloseEnabled
        }
    }

    func isActionable(_ action: Action) -> Bool {
        switch action {
        case .share:
            return video?.isShareable ?? false
        case .addToPlaylist:
            return !(video?.isLocal ?? true)
        case .subscribe:
            return !(video?.isLocal ?? true) && accounts.signedIn && accounts.app.supportsSubscriptions
        case .settings:
            return video != nil
        default:
            return true
        }
    }

    @ViewBuilder func actionBody(_ action: Action) -> some View {
        if isVisible(action) {
            Group {
                switch action {
                case .share:
                    #if os(tvOS)
                        EmptyView()
                    #else
                        ShareButton(contentItem: .init(video: video)) {
                            actionButton("Share", systemImage: "square.and.arrow.up")
                        }
                    #endif
                case .addToPlaylist:
                    actionButton("Add", systemImage: "text.badge.plus") {
                        guard let video else { return }
                        navigation.presentAddToPlaylist(video)
                    }
                case .subscribe:
                    if let channel = video?.channel,
                       subscriptions.isSubscribing(channel.id)
                    {
                        actionButton("Unsubscribe", systemImage: "xmark.circle") {
                            #if os(tvOS)
                                subscriptions.unsubscribe(channel.id)
                            #else
                                navigation.presentUnsubscribeAlert(channel, subscriptions: subscriptions)
                            #endif
                        }
                    } else {
                        actionButton("Subscribe", systemImage: "star.circle") {
                            guard let video else { return }

                            subscriptions.subscribe(video.channel.id) {
                                navigation.sidebarSectionChanged.toggle()
                            }
                        }
                    }
                case .settings:
                    actionButton("Settings", systemImage: "gear") {
                        withAnimation(ControlOverlaysModel.animation) {
                            #if os(tvOS)
                                ControlOverlaysModel.shared.show()
                            #else
                                navigation.presentingPlaybackSettings = true
                            #endif
                        }
                    }
                case .next:
                    actionButton(nextLabel, systemImage: Constants.nextSystemImage) {
                        WatchNextViewModel.shared.userInteractedOpen(player.currentItem)
                    }
                case .hide:
                    actionButton("Hide", systemImage: "chevron.down") {
                        player.hide(animate: true)
                    }

                case .close:
                    actionButton("Close", systemImage: "xmark") {
                        if player.presentingPlayer, openWatchNextOnClose {
                            player.pause()
                            WatchNextViewModel.shared.closed(player.currentItem)
                        } else {
                            player.closeCurrentItem()
                        }
                    }
                }
            }
            .disabled(!isActionable(action))
        }
    }

    var nextLabel: String {
        if actionButtonNextQueueCountEnabled, !player.queue.isEmpty {
            return "\("Next".localized()) • \(player.queue.count)"
        }

        return "Next".localized()
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
