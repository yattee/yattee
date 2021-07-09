import Defaults
import SwiftUI

struct VideoContextMenuView: View {
    @Default(.tabSelection) var tabSelection

    let video: Video

    @Default(.openVideoID) var openVideoID
    @Default(.showingVideoDetails) var showDetails

    @Default(.showingAddToPlaylist) var showingAddToPlaylist
    @Default(.videoIDToAddToPlaylist) var videoIDToAddToPlaylist

    var body: some View {
        if tabSelection == .channel {
            closeChannelButton(from: video)
        } else {
            openChannelButton(from: video)
        }

        openVideoDetailsButton

        if tabSelection == .playlists {
            removeFromPlaylistButton
        } else {
            addToPlaylistButton
        }
    }

    func openChannelButton(from video: Video) -> some View {
        Button("\(video.author) Channel") {
            Defaults[.openChannel] = Channel.from(video: video)
            tabSelection = .channel
        }
    }

    func closeChannelButton(from video: Video) -> some View {
        Button("Close \(Channel.from(video: video).name) Channel") {
            Defaults.reset(.openChannel)
        }
    }

    var openVideoDetailsButton: some View {
        Button("Open video details") {
            openVideoID = video.id
            showDetails = true
        }
    }

    var addToPlaylistButton: some View {
        Button("Add to playlist...") {
            videoIDToAddToPlaylist = video.id
            showingAddToPlaylist = true
        }
    }

    var removeFromPlaylistButton: some View {
        Button("Remove from playlist", role: .destructive) {
            let resource = InvidiousAPI.shared.playlistVideo(Defaults[.selectedPlaylistID]!, video.indexID!)
            resource.request(.delete).onSuccess { _ in
                InvidiousAPI.shared.playlists.load()
            }
        }
    }
}
