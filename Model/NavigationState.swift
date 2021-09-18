import Foundation
import SwiftUI

final class NavigationState: ObservableObject {
    enum TabSelection: Hashable {
        case watchNow, subscriptions, popular, trending, playlists, channel(String), playlist(String), search
    }

    @Published var tabSelection: TabSelection = .watchNow

    @Published var showingVideoDetails = false
    @Published var showingVideo = false
    @Published var video: Video?

    @Published var returnToDetails = false

    @Published var presentingPlaylistForm = false
    @Published var editedPlaylist: Playlist!

    @Published var presentingUnsubscribeAlert = false
    @Published var channelToUnsubscribe: Channel!

    @Published var openChannels = Set<Channel>()
    @Published var isChannelOpen = false
    @Published var sidebarSectionChanged = false

    func openChannel(_ channel: Channel) {
        openChannels.insert(channel)

        isChannelOpen = true
    }

    func closeChannel(_ channel: Channel) {
        guard openChannels.remove(channel) != nil else {
            return
        }

        isChannelOpen = !openChannels.isEmpty

        if tabSelection == .channel(channel.id) {
            tabSelection = .subscriptions
        }
    }

    func showOpenChannel(_ id: Channel.ID) -> Bool {
        if case .channel = tabSelection {
            return false
        } else {
            return !openChannels.contains { $0.id == id }
        }
    }

    func openVideoDetails(_ video: Video) {
        self.video = video
        showingVideoDetails = true
    }

    func closeVideoDetails() {
        showingVideoDetails = false
        video = nil
    }

    func playVideo(_ video: Video) {
        self.video = video
        showingVideo = true
    }

    func showVideoDetailsIfNeeded() {
        showingVideoDetails = returnToDetails
        returnToDetails = false
    }

    var tabSelectionOptionalBinding: Binding<TabSelection?> {
        Binding<TabSelection?>(
            get: {
                self.tabSelection
            },
            set: { newValue in
                if newValue != nil {
                    self.tabSelection = newValue!
                }
            }
        )
    }

    func presentEditPlaylistForm(_ playlist: Playlist?) {
        editedPlaylist = playlist
        presentingPlaylistForm = editedPlaylist != nil
    }

    func presentNewPlaylistForm() {
        editedPlaylist = nil
        presentingPlaylistForm = true
    }

    func presentUnsubscribeAlert(_ channel: Channel?) {
        channelToUnsubscribe = channel
        presentingUnsubscribeAlert = channelToUnsubscribe != nil
    }
}

typealias TabSelection = NavigationState.TabSelection
