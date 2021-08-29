import Foundation
import SwiftUI

final class NavigationState: ObservableObject {
    enum TabSelection: Hashable {
        case subscriptions, popular, trending, playlists, channel(String), playlist(String), search
    }

    @Published var tabSelection: TabSelection = .subscriptions

    @Published var showingChannel = false
    @Published var channel: Channel?

    @Published var showingVideoDetails = false
    @Published var showingVideo = false
    @Published var video: Video?

    @Published var returnToDetails = false

    @Published var presentingPlaylistForm = false
    @Published var editedPlaylist: Playlist!

    @Published var presentingUnsubscribeAlert = false
    @Published var channelToUnsubscribe: Channel!

    func openChannel(_ channel: Channel) {
        returnToDetails = false
        self.channel = channel
        showingChannel = true
    }

    func closeChannel() {
        showingChannel = false
        channel = nil
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
            set: {
                self.tabSelection = $0 ?? .subscriptions
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
