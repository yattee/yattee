import Defaults
import SwiftUI

struct VideosView: View {
    @EnvironmentObject private var profile: Profile

    var videos: [Video]

    @Default(.layout) var layout
    @Default(.tabSelection) var tabSelection

    @State private var showingViewOptions = false

    var body: some View {
        VStack {
            if layout == .cells {
                VideosCellsView(videos: videos, columns: self.profile.cellsColumns)
            } else {
                VideosListView(videos: videos)
            }
        }
        .fullScreenCover(isPresented: $showingViewOptions) { ViewOptionsView() }
        .onPlayPauseCommand { showingViewOptions.toggle() }
    }
}
