import SwiftUI

struct ContentView: View {
    @ObservedObject private var popular = PopluarVideosProvider()

    var items: [GridItem] {
        Array(repeating: .init(.flexible()), count: 4)
    }

    var body: some View {
        NavigationView {
            TabView {
                Group {
                    List {
                        ForEach(popular.videos) { video in
                            VideoThumbnailView(video: video)
                                .listRowInsets(EdgeInsets(top: .zero, leading: .zero, bottom: .zero, trailing: 30))
                        }
                    }
                    .listStyle(GroupedListStyle())
                }
                .tabItem { Text("Popular") }
            }
        }
        .task {
            async {
                popular.load()
            }
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
