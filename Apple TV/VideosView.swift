import Defaults
import SwiftUI

struct VideosView: View {
    @State private var profile = Profile()
    
    @Default(.layout) var layout
    @Default(.tabSelection) var tabSelection

    var videos: [Video]
    
    var body: some View {
        Group {
            if layout == .cells {
                VideosCellsView(videos: videos, columns: self.profile.cellsColumns)
            } else {
                VideosListView(videos: videos)
            }
        }
    }
}
