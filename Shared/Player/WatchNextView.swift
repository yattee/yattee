import Defaults
import SwiftUI

struct WatchNextView: View {
    @ObservedObject private var model = WatchNextViewModel.shared
    @ObservedObject private var player = PlayerModel.shared

    @Default(.saveHistory) private var saveHistory

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Group {
            if model.isPresenting {
                #if os(iOS)
                    NavigationView {
                        watchNext
                            .toolbar {
                                ToolbarItem(placement: .principal) {
                                    watchNextMenu
                                }
                            }
                    }
                    .navigationViewStyle(.stack)
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
                                #if os(macOS)
                                    Text("Mode")
                                        .foregroundColor(.secondary)
                                #endif

                                playbackModeControl

                                HStack {
                                    if model.isRestartable {
                                        reopenButton
                                    }
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
        }
        .transition(.opacity)
        .zIndex(0)
        #if os(tvOS)
            .background(Color.background(scheme: colorScheme))
        #else
            .background(Color.background)
        #endif
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

                    Divider()
                        .padding(.vertical, 5)
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
                playbackModePicker
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
            Text(model.page == .queue ? queueTitle : model.page.title)
                .font(.headline)
        }
    }

    var pagePicker: some View {
        Picker("Page", selection: $model.page) {
            ForEach(WatchNextViewModel.Page.allCases, id: \.rawValue) { page in
                Label(
                    page == .queue ? queueTitle : page.title,
                    systemImage: page.systemImageName
                )
                .tag(page)
            }
        }
    }

    var queueTitle: String {
        "\(WatchNextViewModel.Page.queue.title) • \(player.queue.count)"
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
            Label("Hide", systemImage: "xmark")
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

    var queueForMoreVideos: [ContentItem] {
        guard !player.queue.isEmpty else { return [] }

        let suffix = player.playbackMode == .queue && model.isAutoplaying && model.canAutoplay ? 1 : 0
        return player.queue.suffix(from: suffix).map(\.contentItem)
    }

    @ViewBuilder var moreVideos: some View {
        VStack(spacing: 12) {
            switch model.page {
            case .queue:

                if player.playbackMode == .related, !(model.isAutoplaying && model.canAutoplay) {
                    autoplaying

                    Divider()
                }

                if (model.isAutoplaying && model.canAutoplay && !queueForMoreVideos.isEmpty) ||
                    (!model.isAutoplaying && !queueForMoreVideos.isEmpty)
                {
                    HStack {
                        Text("Next in queue")
                            .font(.headline)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        Spacer()

                        ClearQueueButton()
                    }
                }

                if !queueForMoreVideos.isEmpty {
                    LazyVStack {
                        ForEach(queueForMoreVideos) { item in
                            ContentItemView(item: item)
                                .environment(\.inQueueListing, true)
                                .environment(\.listingStyle, .list)
                        }
                    }
                } else {
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

    @ViewBuilder var playbackModeControl: some View {
        #if os(tvOS)
            Button {
                player.playbackMode = player.playbackMode.next()
            } label: {
                Label(player.playbackMode.description, systemImage: player.playbackMode.systemImage)
                    .transaction { t in t.animation = nil }
                    .frame(minWidth: 350)
            }
        #elseif os(macOS)
            playbackModePicker
                .modifier(SettingsPickerModifier())
            #if os(macOS)
                .frame(maxWidth: 150)
            #endif
        #else
            Menu {
                playbackModePicker
            } label: {
                Label(player.playbackMode.description, systemImage: player.playbackMode.systemImage)
            }
        #endif
    }

    var playbackModePicker: some View {
        Picker("Playback Mode", selection: $model.player.playbackMode) {
            ForEach(PlayerModel.PlaybackMode.allCases, id: \.rawValue) { mode in
                Label(mode.description, systemImage: mode.systemImage).tag(mode)
            }
        }
        .labelsHidden()
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
                .font(.headline)
            Spacer()
            Button {
                player.setRelatedAutoplayItem()
            } label: {
                Label("Find Other", systemImage: "arrow.triangle.2.circlepath.circle")
                    .labelStyle(.iconOnly)
                    .foregroundColor(.accentColor)
            }
            .disabled(player.currentItem.isNil)
            .buttonStyle(.plain)
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
