import SwiftUI

struct SearchedVideosView: View {
    @ObservedObject var provider = SearchedVideosProvider()

    @Binding var query: String

    var body: some View {
        Group {
            List {
                ForEach(videos) { video in
                    VideoThumbnailView(video: video)
                        .listRowInsets(listRowInsets)
                }
            }
            .listStyle(GroupedListStyle())
        }
    }

    var listRowInsets: EdgeInsets {
        EdgeInsets(top: .zero, leading: .zero, bottom: .zero, trailing: 30)
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

// struct SearchedVideosView_Previews: PreviewProvider {
//    static var previews: some View {
//        SearchedVideosView()
//    }
// }
