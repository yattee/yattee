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
        var newQuery = query

        if let url = URLComponents(string: query),
           let queryItem = url.queryItems?.first(where: { item in item.name == "v" }),
           let id = queryItem.value
        {
            newQuery = id
        }

        if newQuery != provider.query {
            provider.query = newQuery
            provider.load()
        }

        return provider.videos
    }
}
