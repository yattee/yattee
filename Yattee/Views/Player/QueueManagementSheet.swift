//
//  QueueManagementSheet.swift
//  Yattee
//
//  Sheet for managing the player queue with reorder and remove capabilities.
//

import SwiftUI

struct QueueManagementSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appEnvironment) private var appEnvironment

    private var queueManager: QueueManager? { appEnvironment?.queueManager }
    private var playerService: PlayerService? { appEnvironment?.playerService }
    private var playerState: PlayerState? { playerService?.state }
    private var navigationCoordinator: NavigationCoordinator? { appEnvironment?.navigationCoordinator }

    private var queue: [QueuedVideo] { playerState?.queue ?? [] }
    private var history: [QueuedVideo] { playerState?.history ?? [] }
    private var isLoadingMore: Bool { queueManager?.isLoadingMore ?? false }
    private var hasMoreItems: Bool { queueManager?.hasMoreItems() ?? false }
    private var queueSourceLabel: String? { queueManager?.currentQueueSourceLabel }
    private var listStyle: VideoListStyle { appEnvironment?.settingsManager.listStyle ?? .inset }

    var body: some View {
        NavigationStack {
            Group {
                if queue.isEmpty && history.isEmpty && playerState?.currentVideo == nil {
                    emptyStateView
                } else {
                    queueListView
                }
            }
            .navigationTitle(queueSourceLabel ?? String(localized: "queue.sheet.title"))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    queueModeMenu
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(role: .cancel) {
                        dismiss()
                    } label: {
                        Label(String(localized: "common.close"), systemImage: "xmark")
                            .labelStyle(.iconOnly)
                    }
                }
            }
        }
        .presentationDragIndicator(.visible)
        .presentationDetents([.medium, .large])
    }

    // MARK: - Views

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "list.bullet")
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)

            Text(String(localized: "queue.sheet.empty"))
                .font(.headline)
                .foregroundStyle(.secondary)

            Text(String(localized: "queue.sheet.emptyHint"))
                .font(.subheadline)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var queueListView: some View {
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
                                    playFromHistory(at: index)
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
                        nowPlayingHeader
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
                                    queueManager?.removeFromQueue(at: index)
                                },
                                onTap: {
                                    playVideo(at: index)
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
            #if os(tvOS)
            .listStyle(.grouped)
            #elseif os(iOS)
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

    /// Header for Now Playing section
    @ViewBuilder
    private var nowPlayingHeader: some View {
        Text(String(localized: "queue.section.nowPlaying"))
    }

    /// Menu for selecting queue mode (shuffle, repeat, etc.)
    @ViewBuilder
    private var queueModeMenu: some View {
        Menu {
            ForEach(QueueMode.allCases, id: \.self) { mode in
                Button {
                    playerState?.queueMode = mode
                } label: {
                    Label(mode.displayName, systemImage: mode.icon)
                }
                .disabled(playerState?.queueMode == mode)
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: playerState?.queueMode.icon ?? "list.bullet")
                Image(systemName: "chevron.down")
                    .font(.caption2)
            }
            .foregroundStyle(.tint)
        }
    }

    // MARK: - Actions

    private func playVideo(at index: Int) {
        guard let playerService, let playerState else { return }
        guard index < queue.count else { return }
        let queuedVideo = queue[index]

        // Push current video to history before switching (skip if incognito or history disabled)
        if let currentVideo = playerState.currentVideo,
           appEnvironment?.settingsManager.incognitoModeEnabled != true,
           appEnvironment?.settingsManager.saveWatchHistory != false {
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
               appEnvironment?.settingsManager.incognitoModeEnabled != true,
               appEnvironment?.settingsManager.saveWatchHistory != false {
                playerState.pushToHistory(item)
            }
            queueManager?.removeFromQueue(at: 0)
        }
        // Remove the one we're about to play
        queueManager?.removeFromQueue(at: 0)

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
        navigationCoordinator?.isMiniPlayerQueueSheetPresented = false
        dismiss()
    }

    private func playFromHistory(at index: Int) {
        guard let playerService, let playerState else { return }
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
        navigationCoordinator?.isMiniPlayerQueueSheetPresented = false
        dismiss()
    }
}

#Preview {
    Text("Tap to open")
        .sheet(isPresented: .constant(true)) {
            QueueManagementSheet()
        }
}
