import SwiftUI

struct HistoryView: View {
    var limit = 10

    @FetchRequest(sortDescriptors: [.init(key: "watchedAt", ascending: false)])
    var watches: FetchedResults<Watch>

    @ObservedObject private var player = PlayerModel.shared

    @State private var visibleWatches = [Watch]()

    init(limit: Int = 10) {
        self.limit = limit
    }

    var body: some View {
        LazyVStack {
            if visibleWatches.isEmpty {
                VStack(spacing: 20) {
                    HStack {
                        Image(systemName: "clock")
                        Text("Playback history is empty")
                    }.foregroundColor(.secondary)
                }
            } else {
                ForEach(visibleWatches, id: \.videoID) { watch in
                    let video = player.historyVideo(watch.videoID) ?? watch.video

                    ContentItemView(item: .init(video: video))
                        .environment(\.listingStyle, .list)
                        .contextMenu {
                            VideoContextMenuView(video: video)
                        }
                }
            }
        }
        .animation(nil, value: visibleWatches)
        .onAppear(perform: reloadVisibleWatches)
        .onChange(of: player.currentVideo) { _ in reloadVisibleWatches() }
    }

    func reloadVisibleWatches() {
        visibleWatches = Array(watches.filter { $0.videoID != player.currentVideo?.videoID }.prefix(limit))
        visibleWatches.forEach(player.loadHistoryVideoDetails)
    }
}

struct HistoryView_Previews: PreviewProvider {
    static var previews: some View {
        HistoryView()
    }
}
