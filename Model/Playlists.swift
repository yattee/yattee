import Foundation
import Siesta
import SwiftUI

final class Playlists: ObservableObject {
    @Published var playlists = [Playlist]()

    var resource: Resource {
        InvidiousAPI.shared.playlists
    }

    init() {
        load()
    }

    var all: [Playlist] {
        playlists.sorted { $0.title.lowercased() < $1.title.lowercased() }
    }

    func find(id: Playlist.ID) -> Playlist? {
        all.first { $0.id == id }
    }

    func reload() {
        load()
    }

    fileprivate func load() {
        resource.load().onSuccess { resource in
            if let playlists: [Playlist] = resource.typedContent() {
                self.playlists = playlists
            }
        }
    }
}
