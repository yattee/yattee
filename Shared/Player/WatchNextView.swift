import Defaults
import SwiftUI

struct WatchNextView: View {
    @ObservedObject private var model = WatchNextViewModel.shared
    @ObservedObject private var player = PlayerModel.shared

    @Default(.saveHistory) private var saveHistory

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Group {
            #if os(iOS)
                NavigationView {
                    watchNext
                }
            #else
                VStack {
                    HStack {
                        closeButton
                        Spacer()
                        reopenButton
                    }
                    .padding()
                    watchNext
                }
            #endif
        }
        #if os(tvOS)
        .background(Color.background(scheme: colorScheme))
        #else
        .background(Color.background)
        #endif
        .opacity(model.presentingOutro ? 1 : 0)
    }

    var watchNext: some View {
        ScrollView {
            VStack(alignment: .leading) {
                if model.isAutoplaying,
                   let item = nextFromTheQueue
                {
                    HStack {
                        Text("Playing Next in 5...")
                            .font(.headline)
                        Spacer()

                        Button {
                            model.cancelAutoplay()
                        } label: {
                            Label("Cancel", systemImage: "xmark")
                        }
                    }

                    PlayerQueueRow(item: item)
                        .padding(.bottom, 10)
                }
                moreVideos
            }
            .padding(.horizontal)
        }
        .navigationBarTitleDisplayMode(.inline)
        .navigationTitle("Watch Next")
        #if !os(macOS)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    closeButton
                }

                ToolbarItem(placement: .primaryAction) {
                    reopenButton
                }
            }
        #endif
    }

    var closeButton: some View {
        Button {
            player.closeCurrentItem()
            player.hide(animate: true)
            Delay.by(0.8) {
                model.presentingOutro = false
            }
        } label: {
            Label("Close", systemImage: "xmark")
        }
    }

    @ViewBuilder var reopenButton: some View {
        if player.currentItem != nil, model.item != nil {
            Button {
                model.close()
            } label: {
                Label("Back to last video", systemImage: "arrow.counterclockwise")
            }
        }
    }

    @ViewBuilder var moreVideos: some View {
        VStack(spacing: 12) {
            let queueForMoreVideos = player.queue.isEmpty ? [] : player.queue.suffix(from: model.isAutoplaying ? 1 : 0)
            if !queueForMoreVideos.isEmpty {
                VStack(spacing: 12) {
                    Text("Next in Queue")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .font(.headline)

                    ForEach(queueForMoreVideos) { item in
                        ContentItemView(item: .init(video: item.video))
                            .environment(\.listingStyle, .list)
                    }
                }
            }

            if let item = model.item {
                VStack(spacing: 12) {
                    Text("Related videos")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .font(.headline)

                    ForEach(item.video.related) { video in
                        ContentItemView(item: .init(video: video))
                            .environment(\.listingStyle, .list)
                    }
                    .padding(.bottom, 4)
                }
            }

            if saveHistory {
                VStack(spacing: 12) {
                    Text("History")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .font(.headline)

                    HStack {
                        Text("Playing Next in 5...")
                            .font(.headline)
                        Spacer()

                        Button {
                            model.cancelAutoplay()
                        } label: {
                            Label("Cancel", systemImage: "pause.fill")
                        }
                    }

                    HistoryView(limit: 15)
                }
            }
        }
    }

    var nextFromTheQueue: PlayerQueueItem? {
        if player.playbackMode == .related {
            return player.autoplayItem
        } else if player.playbackMode == .queue {
            return player.queue.first
        }

        return nil
    }
}

struct OutroView_Previews: PreviewProvider {
    static var previews: some View {
        WatchNextView()
            .onAppear {
                WatchNextViewModel.shared.prepareForNextItem(.init(.fixture))
            }
    }
}
