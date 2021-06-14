import SwiftUI

struct SearchView: View {
    @ObservedObject private var provider = SearchedVideosProvider()
    @ObservedObject var state: AppState

    @Binding var tabSelection: TabSelection

    @State var query = ""

    var body: some View {
        VideosView(state: state, tabSelection: $tabSelection, videos: videos)
            .searchable(text: $query)
    }

    var videos: [Video] {
        provider.load(query)

        return provider.videos
    }
}
