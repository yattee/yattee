import Foundation
import SwiftUI

struct PopularVideosView: View {
    @ObservedObject private var popular = PopluarVideosProvider()

    var body: some View {
        Group {
            List {
                ForEach(popular.videos) { video in
                    VideoThumbnailView(video: video)
                        .listRowInsets(listRowInsets)
                }
            }
            .listStyle(GroupedListStyle())
        }
        .task {
            async {
                popular.load()
            }
        }
    }
    
    var listRowInsets: EdgeInsets {
        EdgeInsets(top: .zero, leading: .zero, bottom: .zero, trailing: 30)
    }
}
