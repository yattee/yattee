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

    /// Optional dismiss callback used when the view is presented inline (e.g. as
    /// the tvOS half-screen panel) rather than via a sheet/fullScreenCover. When
    /// nil, falls back to `@Environment(\.dismiss)`.
    var onDismiss: (() -> Void)?

    #if os(tvOS)
    /// Identifies which row should receive focus when the inline panel appears.
    /// Necessary because tvOS doesn't auto-focus an inline overlay the way it
    /// does for `fullScreenCover`.
    enum InlinePanelFocus: Hashable {
        case history(String)
        case nowPlaying
        case upNext(String)
    }

    @FocusState var inlinePanelFocus: InlinePanelFocus?

    private var inlinePanelInitialFocusTarget: InlinePanelFocus? {
        if let first = history.first { return .history(first.id) }
        if playerState?.currentVideo != nil { return .nowPlaying }
        if let first = queue.first { return .upNext(first.id) }
        return nil
    }
    #endif

    private func performDismiss() {
        if let onDismiss {
            onDismiss()
        } else {
            dismiss()
        }
    }

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
        #if os(tvOS)
        tvOSPanelBody
        #else
        nonTVOSBody
        #endif
    }

    #if os(tvOS)
    /// Custom layout for the tvOS half-screen inline panel. Bypasses
    /// `NavigationStack` entirely because NavigationStack on tvOS reserves an
    /// asymmetric content area that can't be escaped via `.ignoresSafeArea`
    /// from the inside.
    private var tvOSPanelBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Custom title bar — replaces the NavigationStack toolbar. Uses
            // ZStack so the centered title is decoupled from the leading
            // shuffle button's vertical sizing.
            ZStack {
                Text(queueSourceLabel ?? String(localized: "queue.sheet.title"))
                    .font(.system(size: 32, weight: .semibold))
                    .foregroundStyle(.primary)
                HStack {
                    queueModeMenu
                    Spacer()
                }
            }
            .padding(.horizontal, 80)
            .padding(.top, 32)
            .padding(.bottom, 16)

            if queue.isEmpty && history.isEmpty && playerState?.currentVideo == nil {
                emptyStateView
            } else {
                tvOSQueueListView
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea()
        )
        .onExitCommand { performDismiss() }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                inlinePanelFocus = inlinePanelInitialFocusTarget
            }
        }
    }
    #endif

    private var nonTVOSBody: some View {
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
                #if !os(macOS)
                ToolbarItem(placement: .cancellationAction) {
                    queueModeMenu
                }
                sheetCloseToolbarItem { performDismiss() }
                #endif
            }
            #if os(macOS)
            // On macOS the mode selector and Close button share one bottom bar,
            // with the mode selector pinned to the leading edge so it can show
            // both icon and text.
            .safeAreaInset(edge: .bottom) {
                VStack(spacing: 0) {
                    Divider()
                    HStack {
                        queueModeMenu
                        Spacer()
                        Button(role: .cancel) { performDismiss() } label: {
                            Text(String(localized: "common.close"))
                        }
                        .keyboardShortcut(.cancelAction)
                        .buttonStyle(.borderedProminent)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                }
                .background(.bar)
            }
            #endif
        }
        .presentationDragIndicator(.visible)
        #if os(iOS)
        .presentationDetents([.medium, .large])
        #endif
        #if os(macOS)
        .frame(minWidth: 450, minHeight: 500)
        #endif
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

    @ViewBuilder
    private var queueListView: some View {
        #if os(tvOS)
        // On tvOS the panel uses a ScrollView+VStack instead of a `List` because
        // `.listStyle(.grouped)` introduces an asymmetric leading inset that
        // can't be overridden via `.listRowInsets` — the inset is structural to
        // the grouped style. Custom layout gives us full control over symmetric
        // padding inside the half-screen panel.
        tvOSQueueListView
        #else
        iosQueueListView
        #endif
    }

    #if os(tvOS)
    private var tvOSQueueListView: some View {
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
                                .focused($inlinePanelFocus, equals: .history(historyItem.id))
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
                        .focused($inlinePanelFocus, equals: .nowPlaying)
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
                                .focused($inlinePanelFocus, equals: .upNext(queuedVideo.id))
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
                .padding(.horizontal, 80)
                .padding(.vertical, 24)
            }
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    proxy.scrollTo("now-playing", anchor: .center)
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
    #endif

    private var iosQueueListView: some View {
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
                            #if os(tvOS)
                            .focused($inlinePanelFocus, equals: .history(historyItem.id))
                            // Zero the grouped style's built-in row insets
                            // (which are asymmetric in a half-screen panel) and
                            // apply our own symmetric padding directly to the
                            // row content.
                            .padding(.horizontal, 40)
                            .listRowInsets(EdgeInsets())
                            #endif
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
                        #if os(tvOS)
                        .focused($inlinePanelFocus, equals: .nowPlaying)
                        .listRowInsets(EdgeInsets(top: 6, leading: 40, bottom: 6, trailing: 40))
                        #endif
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
                                    withAnimation {
                                        queueManager?.removeFromQueue(id: queuedVideo.id)
                                    }
                                },
                                onTap: {
                                    playVideo(at: index)
                                }
                            )
                            #if os(tvOS)
                            .focused($inlinePanelFocus, equals: .upNext(queuedVideo.id))
                            // Zero the grouped style's built-in row insets
                            // (which are asymmetric in a half-screen panel) and
                            // apply our own symmetric padding directly to the
                            // row content.
                            .padding(.horizontal, 40)
                            .listRowInsets(EdgeInsets())
                            #endif
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
        #if os(tvOS)
        Button {
            cycleQueueMode()
        } label: {
            Image(systemName: playerState?.queueMode.icon ?? "list.bullet")
                .foregroundStyle(.tint)
        }
        #else
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
                #if os(macOS)
                Text(playerState?.queueMode.displayName ?? QueueMode.normal.displayName)
                #endif
                Image(systemName: "chevron.down")
                    .font(.caption2)
            }
            .foregroundStyle(.tint)
        }
        #if os(macOS)
        // Default Menu style stretches full-width on macOS; keep the button
        // hugging its label so it sits tidily in the bottom-left bar.
        .menuStyle(.borderlessButton)
        .fixedSize()
        #endif
        #endif
    }

    private func cycleQueueMode() {
        guard let playerState else { return }
        let modes = QueueMode.allCases
        let currentIndex = modes.firstIndex(of: playerState.queueMode) ?? 0
        let nextIndex = (currentIndex + 1) % modes.count
        playerState.queueMode = modes[nextIndex]
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
        performDismiss()
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
        performDismiss()
    }
}

#Preview {
    Text("Tap to open")
        .sheet(isPresented: .constant(true)) {
            QueueManagementSheet()
        }
}
