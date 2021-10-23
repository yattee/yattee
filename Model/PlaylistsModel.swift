import Foundation
import Siesta
import SwiftUI

final class PlaylistsModel: ObservableObject {
    @Published var playlists = [Playlist]()

    @Published var selectedPlaylistID: Playlist.ID = ""

    var accounts = AccountsModel()

    init(_ playlists: [Playlist] = [Playlist]()) {
        self.playlists = playlists
    }

    var all: [Playlist] {
        playlists.sorted { $0.title.lowercased() < $1.title.lowercased() }
    }

    func find(id: Playlist.ID) -> Playlist? {
        playlists.first { $0.id == id }
    }

    var isEmpty: Bool {
        playlists.isEmpty
    }

    func load(force: Bool = false, onSuccess: @escaping () -> Void = {}) {
        let request = force ? resource?.load() : resource?.loadIfNeeded()

        request?
            .onSuccess { resource in
                if let playlists: [Playlist] = resource.typedContent() {
                    self.playlists = playlists
                    if self.selectedPlaylistID.isEmpty {
                        self.selectPlaylist(self.all.first?.id)
                    }
                    onSuccess()
                }
            }
            .onFailure { _ in
                self.playlists = []
            }
    }

    func addVideoToCurrentPlaylist(videoID: Video.ID, onSuccess: @escaping () -> Void = {}) {
        let resource = accounts.api.playlistVideos(currentPlaylist!.id)
        let body = ["videoId": videoID]

        resource?.request(.post, json: body).onSuccess { _ in
            self.load(force: true)
            onSuccess()
        }
    }

    func removeVideoFromPlaylist(videoIndexID: String, playlistID: Playlist.ID, onSuccess: @escaping () -> Void = {}) {
        let resource = accounts.api.playlistVideo(playlistID, videoIndexID)

        resource?.request(.delete).onSuccess { _ in
            self.load(force: true)
            onSuccess()
        }
    }

    func selectPlaylist(_ id: String?) {
        selectedPlaylistID = id ?? ""
    }

    private var resource: Resource? {
        accounts.api.playlists
    }

    private var selectedPlaylist: Playlist? {
        guard !selectedPlaylistID.isEmpty else {
            return nil
        }

        return find(id: selectedPlaylistID)
    }

    var currentPlaylist: Playlist? {
        selectedPlaylist ?? all.first
    }
}
