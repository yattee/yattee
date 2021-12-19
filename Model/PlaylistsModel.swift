import Foundation
import Siesta
import SwiftUI

final class PlaylistsModel: ObservableObject {
    @Published var playlists = [Playlist]()

    var accounts = AccountsModel()

    init(_ playlists: [Playlist] = [Playlist]()) {
        self.playlists = playlists
    }

    var all: [Playlist] {
        playlists.sorted { $0.title.lowercased() < $1.title.lowercased() }
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
        onFailure: @escaping (RequestError) -> Void = { _ in }
    ) {
        let resource = accounts.api.playlistVideos(playlistID)
        let body = ["videoId": videoID]

        resource?
            .request(.post, json: body)
            .onSuccess { _ in
                self.load(force: true)
                onSuccess()
            }
            .onFailure(onFailure)
    }

    func removeVideo(videoIndexID: String, playlistID: Playlist.ID, onSuccess: @escaping () -> Void = {}) {
        let resource = accounts.api.playlistVideo(playlistID, videoIndexID)

        resource?.request(.delete).onSuccess { _ in
            self.load(force: true)
            onSuccess()
        }
    }

    private var resource: Resource? {
        accounts.api.playlists
    }
}
