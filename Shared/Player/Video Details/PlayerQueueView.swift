import Defaults
import Foundation
import SwiftUI

struct PlayerQueueView: View {
    var sidebarQueue: Bool

    @FetchRequest(sortDescriptors: [.init(key: "watchedAt", ascending: false)])
    var watches: FetchedResults<Watch>

    @ObservedObject private var player = PlayerModel.shared

    @Default(.saveHistory) private var saveHistory
    @Default(.showRelated) private var showRelated

    var body: some View {
        Group {
            Group {
                if player.playbackMode == .related {
                    autoplaying
                }
                playingNext
                if sidebarQueue, showRelated {
                    related
                }
            }
            .listRowBackground(Color.clear)
            #if !os(iOS)
                .padding(.vertical, 5)
                .listRowInsets(EdgeInsets())
            #endif
            Color.clear.padding(.bottom, 50)
                .listRowBackground(Color.clear)
                .backport
                .listRowSeparator(false)
        }
        .environment(\.inNavigationView, false)
    }

    @ViewBuilder var autoplaying: some View {
        Section(header: autoplayingHeader) {
            if let item = player.autoplayItem {
                PlayerQueueRow(item: item, autoplay: true)
            } else {
                Group {
                    if player.currentItem.isNil {
                        Text("Not Playing")
                    } else {
                        Text("Finding something to play...")
                    }
                }
                .foregroundColor(.secondary)
            }
        }
    }

    var autoplayingHeader: some View {
        HStack {
            Text("Autoplaying Next")
                .foregroundColor(.secondary)
                .font(.caption)
            Spacer()
            Button {
                player.setRelatedAutoplayItem()
            } label: {
                Label("Find Other", systemImage: "arrow.triangle.2.circlepath.circle")
                    .labelStyle(.iconOnly)
            }
            .disabled(player.currentItem.isNil)
            .buttonStyle(.plain)
        }
    }

    var playingNext: some View {
        Section(header: queueHeader) {
            if player.queue.isEmpty {
                Text("Queue is empty")
                    .foregroundColor(.secondary)
            }

            ForEach(player.queue) { item in
                PlayerQueueRow(item: item)
                    .contextMenu {
                        if let video = item.video {
                            VideoContextMenuView(video: video)
                                .environment(\.inQueueListing, true)
                        }
                    }
            }
        }
    }

    var queueHeader: some View {
        Text(sidebarQueue ? "Queue".localized() : "")
        #if !os(macOS)
            .foregroundColor(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
        #endif
    }

    private var visibleWatches: [Watch] {
        watches.filter { $0.videoID != player.currentVideo?.videoID }
    }

    @ViewBuilder private var related: some View {
        if let related = player.currentVideo?.related, !related.isEmpty {
            Section(header: Text("Related")) {
                ForEach(related) { video in
                    PlayerQueueRow(item: PlayerQueueItem(video))
                        .contextMenu {
                            VideoContextMenuView(video: video)
                        }
                        .id(video.videoID)
                }
            }
            .transaction { t in t.disablesAnimations = true }
        }
    }
}

struct PlayerQueueView_Previews: PreviewProvider {
    static var previews: some View {
        VStack {
            PlayerQueueView(sidebarQueue: true)
        }
        .injectFixtureEnvironmentObjects()
    }
}
