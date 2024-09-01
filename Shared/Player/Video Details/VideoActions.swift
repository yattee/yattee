import Defaults
import SwiftUI

struct VideoActions: View {
    enum Action: String, CaseIterable {
        case share
        case addToPlaylist
        case subscribe
        case fullScreen
        case pip
        #if os(iOS)
            case lockOrientation
        #endif
        case restart
        case advanceToNextItem
        case musicMode
        case settings
        case hide
        case close
    }

    @ObservedObject private var accounts = AccountsModel.shared
    var navigation = NavigationModel.shared
    @ObservedObject private var subscriptions = SubscribedChannelsModel.shared
    @ObservedObject private var player = PlayerModel.shared

    var video: Video?

    @Default(.playerActionsButtonLabelStyle) private var playerActionsButtonLabelStyle

    @Default(.actionButtonShareEnabled) private var actionButtonShareEnabled
    @Default(.actionButtonAddToPlaylistEnabled) private var actionButtonAddToPlaylistEnabled
    @Default(.actionButtonSubscribeEnabled) private var actionButtonSubscribeEnabled
    @Default(.actionButtonSettingsEnabled) private var actionButtonSettingsEnabled
    @Default(.actionButtonFullScreenEnabled) private var actionButtonFullScreenEnabled
    @Default(.actionButtonPipEnabled) private var actionButtonPipEnabled
    @Default(.actionButtonLockOrientationEnabled) private var actionButtonLockOrientationEnabled
    @Default(.actionButtonRestartEnabled) private var actionButtonRestartEnabled
    @Default(.actionButtonAdvanceToNextItemEnabled) private var actionButtonAdvanceToNextItemEnabled
    @Default(.actionButtonMusicModeEnabled) private var actionButtonMusicModeEnabled
    @Default(.actionButtonHideEnabled) private var actionButtonHideEnabled
    @Default(.actionButtonCloseEnabled) private var actionButtonCloseEnabled

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
        case .fullScreen:
            return actionButtonFullScreenEnabled
        case .pip:
            return actionButtonPipEnabled
        #if os(iOS)
            case .lockOrientation:
                return actionButtonLockOrientationEnabled
        #endif
        case .restart:
            return actionButtonRestartEnabled
        case .advanceToNextItem:
            return actionButtonAdvanceToNextItemEnabled
        case .musicMode:
            return actionButtonMusicModeEnabled
        case .hide:
            return actionButtonHideEnabled
        case .close:
            return actionButtonCloseEnabled
        }
    }

    func isAnyActionVisible() -> Bool {
        return Action.allCases.contains { isVisible($0) }
    }

    func isActionable(_ action: Action) -> Bool {
        switch action {
        case .share:
            return video?.isShareable ?? false
        case .addToPlaylist:
            return !(video?.isLocal ?? true) && accounts.signedIn
        case .subscribe:
            return !(video?.isLocal ?? true) && accounts.signedIn && accounts.app.supportsSubscriptions
        case .settings:
            return video != nil
        case .fullScreen:
            return video != nil
        case .pip:
            return video != nil
        case .advanceToNextItem:
            return player.isAdvanceToNextItemAvailable
        case .restart:
            return video != nil
        case .musicMode:
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
                case .fullScreen:
                    actionButton("Fullscreen", systemImage: player.fullscreenImage, action: player.toggleFullScreenAction)
                case .pip:
                    actionButton("PiP", systemImage: player.pipImage, active: player.playingInPictureInPicture, action: player.togglePiPAction)
                #if os(iOS)
                    case .lockOrientation:
                        actionButton("Lock", systemImage: player.lockOrientationImage, active: player.isOrientationLocked, action: player.lockOrientationAction)
                #endif
                case .restart:
                    actionButton("Replay", systemImage: "backward.end.fill", action: player.replayAction)
                case .advanceToNextItem:
                    actionButton("Next", systemImage: "forward.fill") {
                        player.advanceToNextItem()
                    }
                case .musicMode:
                    actionButton("Music", systemImage: "music.note", active: player.musicMode, action: player.toggleMusicMode)
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
                case .hide:
                    actionButton("Hide", systemImage: "chevron.down") {
                        player.hide(animate: true)
                    }
                case .close:
                    actionButton("Close", systemImage: "xmark") {
                        player.closeCurrentItem()
                    }
                }
            }
            .disabled(!isActionable(action))
        }
    }

    func actionButton(
        _ name: String,
        systemImage: String,
        active: Bool = false,
        action: @escaping () -> Void = {}
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: systemImage)
                    .frame(width: 20, height: 20)
                    .foregroundColor(active ? Color("AppRedColor") : .primary)
                if playerActionsButtonLabelStyle.text {
                    Text(name.localized())
                        .foregroundColor(active ? Color("AppRedColor") : .primary)
                        .font(.caption2)
                        .allowsTightening(true)
                        .lineLimit(1)
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
