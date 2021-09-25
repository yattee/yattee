import Foundation
import Siesta
import SwiftUI

final class PlaylistsModel: ObservableObject {
    @Published var playlists = [Playlist]()

    @Published var api: InvidiousAPI!

    var resource: Resource {
        api.playlists
    }

    var all: [Playlist] {
        playlists.sorted { $0.title.lowercased() < $1.title.lowercased() }
    }

    func find(id: Playlist.ID) -> Playlist? {
        all.first { $0.id == id }
    }

    func load(force: Bool = false) {
        let request = force ? resource.load() : resource.loadIfNeeded()

        request?
            .onSuccess { resource in
                if let playlists: [Playlist] = resource.typedContent() {
                    self.playlists = playlists
                }
            }
            .onFailure { _ in
                self.playlists = []
            }
    }
}
