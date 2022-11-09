import SwiftUI

struct HistoryView: View {
    @FetchRequest(sortDescriptors: [.init(key: "watchedAt", ascending: false)])
    var watches: FetchedResults<Watch>

    @EnvironmentObject<PlayerModel> private var player

    var limit = 10

    var body: some View {
        LazyVStack {
            ForEach(visibleWatches, id: \.videoID) { watch in
                PlayerQueueRow(
                    item: PlayerQueueItem.from(watch, video: player.historyVideo(watch.videoID)),
                    history: true
                )
                .onAppear {
                    player.loadHistoryVideoDetails(watch.videoID)
                }
                .contextMenu {
                    VideoContextMenuView(video: watch.video)
                }
            }
            #if os(tvOS)
            .padding(.horizontal, 40)
            #else
            .padding(.horizontal, 15)
            #endif
        }
    }

    private var visibleWatches: [Watch] {
        Array(watches.filter { $0.videoID != player.currentVideo?.videoID }.prefix(limit))
    }
}

struct HistoryView_Previews: PreviewProvider {
    static var previews: some View {
        HistoryView()
    }
}
