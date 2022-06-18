import Defaults
import Foundation
import Siesta
import SwiftUI

final class PlaylistsModel: ObservableObject {
    @Published var playlists = [Playlist]()
    @Published var reloadPlaylists = false

    var accounts = AccountsModel()

    init(_ playlists: [Playlist] = [Playlist]()) {
        self.playlists = playlists
    }

    var all: [Playlist] {
        playlists.sorted { $0.title.lowercased() < $1.title.lowercased() }
    }

    var lastUsed: Playlist? {
        find(id: Defaults[.lastUsedPlaylistID])
    }

    func find(id: Playlist.ID?) -> Playlist? {
        if id.isNil {
            return nil
        }

        return playlists.first { $0.id == id! }
    }

    var isEmpty: Bool {
        playlists.isEmpty
    }

    func load(force: Bool = false, onSuccess: @escaping () -> Void = {}) {
        guard accounts.app.supportsUserPlaylists, accounts.signedIn else {
            playlists = []
            return
        }

        let request = force ? resource?.load() : resource?.loadIfNeeded()

        guard !request.isNil else {
            onSuccess()
            return
        }

        request?
            .onSuccess { resource in
                if let playlists: [Playlist] = resource.typedContent() {
                    self.playlists = playlists
                    onSuccess()
                }
            }
            .onFailure { _ in
                self.playlists = []
            }
    }

    func addVideo(
        playlistID: Playlist.ID,
        videoID: Video.ID,
        onSuccess: @escaping () -> Void = {},
        navigation: NavigationModel?,
        onFailure: ((RequestError) -> Void)? = nil
    ) {
        accounts.api.addVideoToPlaylist(
            videoID,
            playlistID,
            onFailure: onFailure ?? { requestError in
                navigation?.presentAlert(
                    title: "Error when adding to playlist",
                    message: "(\(requestError.httpStatusCode ?? -1)) \(requestError.userMessage)"
                )
            }
        ) {
            self.load(force: true) {
                self.reloadPlaylists.toggle()
                onSuccess()
            }
        }
    }

    func removeVideo(index: String, playlistID: Playlist.ID, onSuccess: @escaping () -> Void = {}) {
        accounts.api.removeVideoFromPlaylist(index, playlistID, onFailure: { _ in }) {
            self.load(force: true) {
                self.reloadPlaylists.toggle()
                onSuccess()
            }
        }
    }

    private var resource: Resource? {
        accounts.api.playlists
    }
}
