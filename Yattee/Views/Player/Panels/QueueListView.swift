//
//  QueueListView.swift
//  Yattee
//
//  Shared queue list (history / now playing / up next) used by the queue
//  management sheet, with playback actions reusable by the tvOS queue panel.
//

import SwiftUI

// MARK: - Playback Actions

/// Shared queue playback actions used by `QueueListView` and the tvOS queue panel.
@MainActor
enum QueuePlaybackActions {
    /// Plays the queue item at `index`, pushing the current video and any
    /// skipped items to history.
    static func playVideo(at index: Int, appEnvironment: AppEnvironment?) {
        guard let appEnvironment else { return }
        let playerService = appEnvironment.playerService
        let playerState = playerService.state
        let queueManager = appEnvironment.queueManager
        let settingsManager = appEnvironment.settingsManager

        let queue = playerState.queue
        guard index < queue.count else { return }
        let queuedVideo = queue[index]

        // Push current video to history before switching (skip if incognito or history disabled)
        if let currentVideo = playerState.currentVideo,
           !settingsManager.incognitoModeEnabled,
           settingsManager.saveWatchHistory {
            let currentItem = QueuedVideo(
                video: currentVideo,
                stream: playerState.currentStream,
                audioStream: playerState.currentAudioStream,
                startTime: playerState.currentTime
            )
            playerState.pushToHistory(currentItem)
        }

        // Remove played video and all before it from queue, pushing them to history
        for _ in 0..<index {
            if let item = playerState.queue.first,
               !settingsManager.incognitoModeEnabled,
               settingsManager.saveWatchHistory {
                playerState.pushToHistory(item)
            }
            queueManager.removeFromQueue(at: 0)
        }
        // Remove the one we're about to play
        queueManager.removeFromQueue(at: 0)

        // Play the selected video (always from beginning for queue items)
        // Prefer downloaded content over pre-loaded network streams
        Task {
            await playerService.playPreferringDownloaded(
                video: queuedVideo.video,
                fallbackStream: queuedVideo.stream,
                fallbackAudioStream: queuedVideo.audioStream,
                startTime: 0
            )
        }
    }

    /// Plays the history item at `index`, moving it and the items after it
    /// back into the queue.
    static func playFromHistory(at index: Int, appEnvironment: AppEnvironment?) {
        guard let appEnvironment else { return }
        let playerService = appEnvironment.playerService
        let playerState = playerService.state

        let history = playerState.history
        guard index < history.count else { return }
        let historyItem = history[index]

        // Push current video to front of queue
        if let currentVideo = playerState.currentVideo {
            playerState.insertNext(currentVideo, stream: playerState.currentStream, audioStream: playerState.currentAudioStream)
        }

        // Push all items after this in history to front of queue (in reverse order)
        // so they become "up next" in correct order
        let itemsAfter = Array(history[(index + 1)...])
        for item in itemsAfter.reversed() {
            playerState.insertNext(item.video, stream: item.stream, audioStream: item.audioStream, captions: item.captions)
        }

        // Remove this item and all after it from history
        for _ in index..<history.count {
            _ = playerState.retreatQueue()
        }

        // Play the selected history item
        // Prefer downloaded content over stored network streams
        Task {
            await playerService.playPreferringDownloaded(
                video: historyItem.video,
                fallbackStream: historyItem.stream,
                fallbackAudioStream: historyItem.audioStream,
                startTime: historyItem.startTime
            )
        }
    }
}

// MARK: - Queue List

#if os(iOS) || os(macOS)

/// List of previously played, now playing, and queued videos with reorder,
/// remove, and load-more support.
struct QueueListView: View {
    @Environment(\.appEnvironment) private var appEnvironment

    /// Called after a row tap starts playback (the host dismisses itself).
    var onPlay: (() -> Void)? = nil

    private var queueManager: QueueManager? { appEnvironment?.queueManager }
    private var playerState: PlayerState? { appEnvironment?.playerService.state }

    private var queue: [QueuedVideo] { playerState?.queue ?? [] }
    private var history: [QueuedVideo] { playerState?.history ?? [] }
    private var isLoadingMore: Bool { queueManager?.isLoadingMore ?? false }
    private var hasMoreItems: Bool { queueManager?.hasMoreItems() ?? false }
    private var listStyle: VideoListStyle { appEnvironment?.settingsManager.listStyle ?? .inset }

    var body: some View {
        ScrollViewReader { proxy in
            List {
                // History section - show previously played videos
                if !history.isEmpty {
                    Section {
                        ForEach(Array(history.enumerated()), id: \.element.id) { index, historyItem in
                            QueueItemRow(
                                queuedVideo: historyItem,
                                index: nil,  // History items don't show numbers
                                isCurrentlyPlaying: false,
                                onRemove: { },
                                onTap: {
                                    QueuePlaybackActions.playFromHistory(at: index, appEnvironment: appEnvironment)
                                    onPlay?()
                                }
                            )
                        }
                    } header: {
                        HStack {
                            Text(String(localized: "queue.section.previously"))
                            Spacer()
                            Text(String(localized: "queue.section.count \(history.count)"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                // Now Playing section - show the currently playing video from playerState
                if let currentVideo = playerState?.currentVideo {
                    Section {
                        // Create a temporary QueuedVideo for display
                        let nowPlayingItem = QueuedVideo(
                            video: currentVideo,
                            stream: playerState?.currentStream,
                            queueSource: nil
                        )
                        QueueItemRow(
                            queuedVideo: nowPlayingItem,
                            index: nil,  // Now playing shows waveform, not a number
                            isCurrentlyPlaying: true,
                            onRemove: { },
                            onTap: { }
                        )
                    } header: {
                        Text(String(localized: "queue.section.nowPlaying"))
                    }
                    .id("now-playing")
                }

                // Up Next section - show all queued videos
                if !queue.isEmpty {
                    Section {
                        ForEach(Array(queue.enumerated()), id: \.element.id) { index, queuedVideo in
                            QueueItemRow(
                                queuedVideo: queuedVideo,
                                index: index + 1, // +1 because "Now Playing" is shown as position 1
                                isCurrentlyPlaying: false,
                                onRemove: {
                                    withAnimation {
                                        queueManager?.removeFromQueue(id: queuedVideo.id)
                                    }
                                },
                                onTap: {
                                    QueuePlaybackActions.playVideo(at: index, appEnvironment: appEnvironment)
                                    onPlay?()
                                }
                            )
                        }
                        .onMove { source, destination in
                            guard let fromIndex = source.first else { return }
                            queueManager?.moveQueueItem(from: fromIndex, to: destination)
                        }

                        // Load more indicator
                        if hasMoreItems {
                            HStack {
                                Spacer()
                                if isLoadingMore {
                                    ProgressView()
                                        .controlSize(.small)
                                } else {
                                    Button {
                                        Task {
                                            try? await queueManager?.loadMoreQueueItems()
                                        }
                                    } label: {
                                        Text(String(localized: "queue.sheet.loadMore"))
                                            .font(.subheadline)
                                            .foregroundStyle(.tint)
                                    }
                                }
                                Spacer()
                            }
                            .listRowBackground(Color.clear)
                        }
                    } header: {
                        HStack {
                            Text(String(localized: "queue.section.upNext"))
                            Spacer()
                            Text(String(localized: "queue.section.count \(queue.count)"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            #if os(iOS)
            .if(listStyle == .plain, then: { view in
                view.listStyle(.plain)
            }, else: { view in
                view.listStyle(.insetGrouped)
            })
            #endif
            .onAppear {
                // Scroll to now playing section (no animation for instant positioning)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    proxy.scrollTo("now-playing", anchor: .center)
                }
            }
        }
    }
}

#endif
