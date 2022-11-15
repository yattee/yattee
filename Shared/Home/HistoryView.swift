import SwiftUI

struct HistoryView: View {
    static let detailsPreloadLimit = 50

    var limit = 10

    @FetchRequest(sortDescriptors: [.init(key: "watchedAt", ascending: false)])
    var watches: FetchedResults<Watch>

    @EnvironmentObject<PlayerModel> private var player

    var body: some View {
        LazyVStack {
            if visibleWatches.isEmpty {
                VStack(alignment: .center, spacing: 20) {
                    HStack {
                        Image(systemName: "clock")
                        Text("Playback history is empty")
                    }.foregroundColor(.secondary)
                }
            } else {
                ForEach(visibleWatches, id: \.videoID) { watch in
                    PlayerQueueRow(
                        item: PlayerQueueItem.from(watch, video: player.historyVideo(watch.videoID)),
                        history: true
                    )
                    .contextMenu {
                        VideoContextMenuView(video: player.historyVideo(watch.videoID) ?? watch.video)
                    }
                }
            }
        }
        .onAppear {
            visibleWatches
                .prefix(Self.detailsPreloadLimit)
                .map(\.videoID)
                .forEach(player.loadHistoryVideoDetails)
        }
        #if os(tvOS)
        .padding(.horizontal, 40)
        #else
        .padding(.horizontal, 15)
        #endif
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
