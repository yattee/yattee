import SwiftUI

struct SearchView: View {
    @ObservedObject private var provider = SearchedVideosProvider()
    @EnvironmentObject private var profile: Profile
    @EnvironmentObject private var state: AppState

    @State private var query = ""

    var body: some View {
        VideosView(videos: videos)
            .environmentObject(state)
            .environmentObject(profile)
            .searchable(text: $query)
    }

    var videos: [Video] {
        provider.load(query)

        return provider.videos
    }
}
