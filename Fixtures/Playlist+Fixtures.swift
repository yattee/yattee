import Foundation

extension Playlist {
    static var fixture: Playlist {
        Playlist(id: UUID().uuidString, title: "Relaxing music", visibility: .public, updated: 1)
    }
}
