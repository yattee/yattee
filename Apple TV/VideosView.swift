import SwiftUI

struct VideosView: View {
    @EnvironmentObject private var state: AppState

    @Binding var tabSelection: TabSelection
    var videos: [Video]

    var body: some View {
        Group {
            if state.profile.listing == .list {
                VideosListView(tabSelection: $tabSelection, videos: videos)
            } else {
                VideosCellsView(videos: videos, columns: state.profile.cellsColumns)
            }
        }
    }
}
