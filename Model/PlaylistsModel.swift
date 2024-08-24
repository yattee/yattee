import Defaults
import Foundation
import Siesta
import SwiftUI

final class PlaylistsModel: ObservableObject {
    static var shared = PlaylistsModel()

    @Published var isLoading = false
    @Published var playlists = [Playlist]()
    @Published var reloadPlaylists = false
    @Published var error: RequestError?

    var accounts = AccountsModel.shared

    init(_ playlists: [Playlist] = [Playlist]()) {
        self.playlists = playlists
    }

    var all: [Playlist] {
        playlists.sorted { $0.title.lowercased() < $1.title.lowercased() }
    }

    var editable: [Playlist] {
        all.filter(\.editable)
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
        guard accounts.app.supportsUserPlaylists, let account = accounts.current else {
            playlists = []
            return
        }

        loadCachedPlaylists(account)

        guard accounts.signedIn else { return }

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let request = force ? self.resource?.load() : self.resource?.loadIfNeeded()

            guard !request.isNil else {
                onSuccess()
                return
            }

            self.isLoading = true

            request?
                .onCompletion { [weak self] _ in
                    self?.isLoading = false
                }
                .onSuccess { resource in
                    self.error = nil
                    if let playlists: [Playlist] = resource.typedContent() {
                        DispatchQueue.main.async { [weak self] in
                            guard let self else { return }
                            self.playlists = playlists
                        }
                        PlaylistsCacheModel.shared.storePlaylist(account: account, playlists: playlists)
                        onSuccess()
                    }
                }
                .onFailure { self.error = $0 }
        }
    }

    private func loadCachedPlaylists(_ account: Account) {
        let cache = PlaylistsCacheModel.shared.retrievePlaylists(account: account)
        if !cache.isEmpty {
            DispatchQueue.main.async(qos: .userInteractive) {
                self.playlists = cache
            }
        }
    }

    func addVideo(
        playlistID: Playlist.ID,
        videoID: Video.ID,
        onSuccess: @escaping () -> Void = {},
        onFailure: ((RequestError) -> Void)? = nil
    ) {
        accounts.api.addVideoToPlaylist(
            videoID,
            playlistID,
            onFailure: onFailure ?? { requestError in
                NavigationModel.shared.presentAlert(
                    title: "Error when adding to playlist",
                    message: "(\(requestError.httpStatusCode ?? -1)) \(requestError.userMessage)"
                )
            }
        ) {
            self.load(force: true) {
                Defaults[.lastUsedPlaylistID] = playlistID
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

    func onAccountChange() {
        error = nil
        playlists = []
        load()
    }
}
