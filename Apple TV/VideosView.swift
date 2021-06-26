import Defaults
import SwiftUI

struct VideosView: View {
    @EnvironmentObject private var profile: Profile

    var videos: [Video]

    @Default(.layout) var layout
    @Default(.tabSelection) var tabSelection

    @State private var showingViewOptions = false

    var body: some View {
        Section {
            if layout == .list {
                VideosListView(videos: videos)
            } else {
                VideosCellsView(videos: videos, columns: self.profile.cellsColumns)
            }
        }
        .fullScreenCover(isPresented: $showingViewOptions) { ViewOptionsView() }
        .onPlayPauseCommand { showingViewOptions.toggle() }
    }
}
