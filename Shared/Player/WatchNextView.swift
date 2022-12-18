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
                        .toolbar {
                            ToolbarItem(placement: .principal) {
                                watchNextMenu
                            }
                        }
                }
            #else
                VStack {
                    HStack {
                        hideCloseButton
                            .labelStyle(.iconOnly)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        Spacer()

                        watchNextMenu
                            .frame(maxWidth: .infinity)

                        Spacer()

                        HStack {
                            if model.isRestartable {
                                reopenButton
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                    #if os(macOS)
                    .padding()
                    #endif
                    watchNext
                }
            #endif
        }
        #if os(tvOS)
        .background(Color.background(scheme: colorScheme))
        #else
        .background(Color.background)
        #endif
        .opacity(model.isPresenting ? 1 : 0)
    }

    var watchNext: some View {
        ScrollView {
            VStack(alignment: .leading) {
                if model.isAutoplaying,
                   let item = model.nextFromTheQueue
                {
                    HStack {
                        Text("Playing Next in \(Int(model.countdown.rounded()))...")
                            .font(.headline.monospacedDigit())
                        Spacer()

                        Button {
                            model.keepFromAutoplaying()
                        } label: {
                            Label("Cancel", systemImage: "pause.fill")
                            #if os(iOS)
                                .imageScale(.large)
                                .padding([.vertical, .leading])
                                .font(.headline.bold())
                            #endif
                        }
                    }
                    #if os(tvOS)
                    .padding(.top, 10)
                    #endif

                    PlayerQueueRow(item: item)
                }

                moreVideos
                    .padding(.top, 15)
            }
            .padding(.horizontal)
        }
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        #if !os(macOS)
        .navigationTitle(model.page.title)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                hideCloseButton
            }

            ToolbarItem(placement: .primaryAction) {
                reopenButton
            }
        }
        #endif
    }

    var watchNextMenu: some View {
        #if os(tvOS)
            Button {
                model.page = model.page.next()
            } label: {
                menuLabel
            }
        #elseif os(macOS)
            pagePicker
                .modifier(SettingsPickerModifier())
            #if os(macOS)
                .frame(maxWidth: 150)
            #endif
        #else
            Menu {
                pagePicker
            } label: {
                HStack(spacing: 12) {
                    menuLabel
                        .foregroundColor(.primary)

                    Image(systemName: "chevron.down.circle.fill")
                        .foregroundColor(.accentColor)
                        .imageScale(.small)
                }
                .transaction { t in t.animation = nil }
            }

        #endif
    }

    var menuLabel: some View {
        HStack {
            Image(systemName: model.page.systemImageName)
                .imageScale(.small)
            Text(model.page.title)
                .font(.headline)
        }
    }

    var pagePicker: some View {
        Picker("Page", selection: $model.page) {
            ForEach(WatchNextViewModel.Page.allCases, id: \.rawValue) { page in
                Label(page.title, systemImage: page.systemImageName)
                    .tag(page)
            }
        }
    }

    @ViewBuilder var hideCloseButton: some View {
        if model.isHideable {
            hideButton
        } else {
            closeButton
        }
    }

    var hideButton: some View {
        Button {
            model.hide()
        } label: {
            Label("Hide", systemImage: "chevron.down")
        }
    }

    var closeButton: some View {
        Button {
            model.close()
        } label: {
            Label("Close", systemImage: "xmark")
        }
    }

    @ViewBuilder var reopenButton: some View {
        if model.isRestartable {
            Button {
                model.restart()
            } label: {
                Label(model.reason == .userInteracted ? "Back" : "Reopen", systemImage: "arrow.counterclockwise")
            }
        }
    }

    @ViewBuilder var moreVideos: some View {
        VStack(spacing: 12) {
            switch model.page {
            case .queue:
                let queueForMoreVideos = player.queue.isEmpty ? [] : player.queue.suffix(from: model.isAutoplaying ? 1 : 0)
                if !queueForMoreVideos.isEmpty {
                    ForEach(queueForMoreVideos) { item in
                        PlayerQueueRow(item: item)
                            .contextMenu {
                                removeButton(item)
                                removeAllButton()

                                if let video = item.video {
                                    VideoContextMenuView(video: video)
                                }
                            }
                        #if os(tvOS)
                            .padding(.horizontal, 30)
                        #endif

                        #if !os(tvOS)
                            Divider()
                        #endif
                    }
                } else if player.playbackMode != .related && player.playbackMode != .loopOne {
                    Label(
                        model.isAutoplaying ? "Nothing more in the queue" : "Queue is empty",
                        systemImage: WatchNextViewModel.Page.queue.systemImageName
                    )
                    .foregroundColor(.secondary)
                }
            case .related:
                if let item = model.item {
                    ForEach(item.video.related) { video in
                        ContentItemView(item: .init(video: video))
                            .environment(\.listingStyle, .list)
                    }
                } else {
                    Label("Nothing was played",
                          systemImage: WatchNextViewModel.Page.related.systemImageName)
                        .foregroundColor(.secondary)
                }
            case .history:
                if saveHistory {
                    HistoryView(limit: 15)
                }
            }
        }
    }

    private func removeButton(_ item: PlayerQueueItem) -> some View {
        Button {
            player.remove(item)
        } label: {
            Label("Remove from the queue", systemImage: "trash")
        }
    }

    private func removeAllButton() -> some View {
        Button {
            player.removeQueueItems()
        } label: {
            Label("Clear the queue", systemImage: "trash.fill")
        }
    }
}

struct WatchNextView_Previews: PreviewProvider {
    static var previews: some View {
        WatchNextView()
            .onAppear {
                WatchNextViewModel.shared.finishedWatching(.init(.fixture))
            }
    }
}
