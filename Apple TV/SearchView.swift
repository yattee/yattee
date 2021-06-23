import SwiftUI

struct SearchView: View {
    @ObservedObject private var provider = SearchedVideosProvider()
    @EnvironmentObject private var state: AppState

    @Binding var tabSelection: TabSelection

    @State private var query = ""

    var body: some View {
        VideosView(tabSelection: $tabSelection, videos: videos)
            .environmentObject(state)
            .searchable(text: $query)
    }

    var videos: [Video] {
        provider.load(query)

        return provider.videos
    }
}
