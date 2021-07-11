import Defaults
import SwiftUI

struct VideoContextMenuView: View {
    @EnvironmentObject<NavigationState> private var navigationState

    let video: Video

    @Default(.showingAddToPlaylist) var showingAddToPlaylist
    @Default(.videoIDToAddToPlaylist) var videoIDToAddToPlaylist

    var body: some View {
        if navigationState.tabSelection == .channel {
            closeChannelButton(from: video)
        } else {
            openChannelButton(from: video)
        }

        openVideoDetailsButton

        if navigationState.tabSelection == .playlists {
            removeFromPlaylistButton
        } else {
            addToPlaylistButton
        }
    }

    func openChannelButton(from video: Video) -> some View {
        Button("\(video.author) Channel") {
            navigationState.openChannel(Channel.from(video: video))
        }
    }

    func closeChannelButton(from video: Video) -> some View {
        Button("Close \(Channel.from(video: video).name) Channel") {
            navigationState.closeChannel()
        }
    }

    var openVideoDetailsButton: some View {
        Button("Open video details") {
            navigationState.openVideoDetails(video)
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
