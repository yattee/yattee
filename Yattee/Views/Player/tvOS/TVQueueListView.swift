//
//  TVQueueListView.swift
//  Yattee
//
//  Focus-based queue list (history / now playing / up next) shared by the
//  half-screen queue panel and the details panel queue page.
//

#if os(tvOS)
import SwiftUI

struct TVQueueListView: View {
    /// Horizontal content padding. The standalone half-screen panel uses 80;
    /// the details panel page passes its own smaller inset.
    var horizontalPadding: CGFloat = 80

    /// Whether the list should grab focus shortly after appearing. Needed for
    /// the inline half-screen panel, which tvOS doesn't auto-focus the way it
    /// does a `fullScreenCover`; the details panel page keeps focus on its
    /// page switcher instead.
    var autoFocusOnAppear = false

    /// Called after a row selection triggers playback.
    var onDidSelectVideo: (() -> Void)?

    @Environment(\.appEnvironment) private var appEnvironment

    /// Identifies which row should receive focus when the list appears.
    enum QueueListFocus: Hashable {
        case history(String)
        case nowPlaying
        case upNext(String)
    }

    @FocusState private var listFocus: QueueListFocus?

    private var initialFocusTarget: QueueListFocus? {
        if let first = history.first { return .history(first.id) }
        if playerState?.currentVideo != nil { return .nowPlaying }
        if let first = queue.first { return .upNext(first.id) }
        return nil
    }

    private var queueManager: QueueManager? { appEnvironment?.queueManager }
    private var playerState: PlayerState? { appEnvironment?.playerService.state }

    private var queue: [QueuedVideo] { playerState?.queue ?? [] }
    private var history: [QueuedVideo] { playerState?.history ?? [] }
    private var isLoadingMore: Bool { queueManager?.isLoadingMore ?? false }
    private var hasMoreItems: Bool { queueManager?.hasMoreItems() ?? false }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if !history.isEmpty {
                        sectionHeader(
                            String(localized: "queue.section.previously"),
                            count: history.count
                        )
                        VStack(spacing: 20) {
                            ForEach(Array(history.enumerated()), id: \.element.id) { index, historyItem in
                                QueueItemRow(
                                    queuedVideo: historyItem,
                                    index: nil,
                                    isCurrentlyPlaying: false,
                                    onRemove: { },
                                    onTap: { playFromHistory(at: index) }
                                )
                                .focused($listFocus, equals: .history(historyItem.id))
                            }
                        }
                    }

                    if let currentVideo = playerState?.currentVideo {
                        sectionHeader(String(localized: "queue.section.nowPlaying"))
                            .id("now-playing")

                        let nowPlayingItem = QueuedVideo(
                            video: currentVideo,
                            stream: playerState?.currentStream,
                            queueSource: nil
                        )
                        QueueItemRow(
                            queuedVideo: nowPlayingItem,
                            index: nil,
                            isCurrentlyPlaying: true,
                            onRemove: { },
                            onTap: { }
                        )
                        .focused($listFocus, equals: .nowPlaying)
                    }

                    if !queue.isEmpty {
                        sectionHeader(
                            String(localized: "queue.section.upNext"),
                            count: queue.count
                        )
                        VStack(spacing: 20) {
                            ForEach(Array(queue.enumerated()), id: \.element.id) { index, queuedVideo in
                                QueueItemRow(
                                    queuedVideo: queuedVideo,
                                    index: index + 1,
                                    isCurrentlyPlaying: false,
                                    onRemove: {
                                        withAnimation {
                                            queueManager?.removeFromQueue(id: queuedVideo.id)
                                        }
                                    },
                                    onTap: { playVideo(at: index) }
                                )
                                .focused($listFocus, equals: .upNext(queuedVideo.id))
                            }

                            if hasMoreItems {
                                HStack {
                                    Spacer()
                                    if isLoadingMore {
                                        ProgressView().controlSize(.small)
                                    } else {
                                        Button {
                                            Task { try? await queueManager?.loadMoreQueueItems() }
                                        } label: {
                                            Text(String(localized: "queue.sheet.loadMore"))
                                                .font(.subheadline)
                                                .foregroundStyle(.tint)
                                        }
                                    }
                                    Spacer()
                                }
                                .padding(.top, 12)
                            }
                        }
                    }
                }
                .padding(.horizontal, horizontalPadding)
                .padding(.vertical, 24)
            }
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    proxy.scrollTo("now-playing", anchor: .center)
                }
                if autoFocusOnAppear {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                        listFocus = initialFocusTarget
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func sectionHeader(_ title: String, count: Int? = nil) -> some View {
        HStack {
            Text(title.uppercased())
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            if let count {
                Text(String(localized: "queue.section.count \(count)"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Actions

    private func playVideo(at index: Int) {
        QueuePlaybackActions.playVideo(at: index, appEnvironment: appEnvironment)
        onDidSelectVideo?()
    }

    private func playFromHistory(at index: Int) {
        QueuePlaybackActions.playFromHistory(at: index, appEnvironment: appEnvironment)
        onDidSelectVideo?()
    }
}

#endif
