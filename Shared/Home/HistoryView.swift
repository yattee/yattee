import SwiftUI

struct HistoryView: View {
    var limit: Int

    @FetchRequest(sortDescriptors: [.init(key: "watchedAt", ascending: false)])
    var watches: FetchedResults<Watch>

    @ObservedObject private var player = PlayerModel.shared
    @State private var visibleWatches = [Watch]()

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
                ListView(items: contentItems, limit: limit)
            }
        }
        .animation(nil, value: visibleWatches)
        .onChange(of: player.currentVideo) { _ in reloadVisibleWatches() }
    }

    var contentItems: [ContentItem] {
        visibleWatches.map { .init(video: player.historyVideo($0.videoID) ?? $0.video) }
    }

    func reloadVisibleWatches() {
        visibleWatches = Array(watches.filter { $0.videoID != player.currentVideo?.videoID }.prefix(limit))
    }

    init(limit: Int = 10) {
        self.limit = limit
    }
}

struct HistoryView_Previews: PreviewProvider {
    static var previews: some View {
        HistoryView(limit: 10)
    }
}
