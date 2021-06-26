import SwiftUI

struct VideosView: View {
    @EnvironmentObject private var profile: Profile

    @Binding var tabSelection: TabSelection
    var videos: [Video]

    @State private var showingViewOptions = false

    var body: some View {
        Section {
            if self.profile.listing == .list {
                VideosListView(tabSelection: $tabSelection, videos: videos)
            } else {
                VideosCellsView(videos: videos, columns: self.profile.cellsColumns)
            }
        }
        .fullScreenCover(isPresented: $showingViewOptions) { ViewOptionsView() }
        .onPlayPauseCommand { showingViewOptions.toggle() }
    }
}
