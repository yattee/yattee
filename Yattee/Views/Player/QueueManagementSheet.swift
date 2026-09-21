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
    private var playerState: PlayerState? { appEnvironment?.playerService.state }
    private var navigationCoordinator: NavigationCoordinator? { appEnvironment?.navigationCoordinator }

    private var queue: [QueuedVideo] { playerState?.queue ?? [] }
    private var history: [QueuedVideo] { playerState?.history ?? [] }
    private var isLoadingMore: Bool { queueManager?.isLoadingMore ?? false }
    private var hasMoreItems: Bool { queueManager?.hasMoreItems() ?? false }
    private var queueSourceLabel: String? { queueManager?.currentQueueSourceLabel }

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
        QueueListView(onPlay: {
            navigationCoordinator?.isMiniPlayerQueueSheetPresented = false
            performDismiss()
        })
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

    #if os(tvOS)
    private func playVideo(at index: Int) {
        QueuePlaybackActions.playVideo(at: index, appEnvironment: appEnvironment)
        navigationCoordinator?.isMiniPlayerQueueSheetPresented = false
        performDismiss()
    }

    private func playFromHistory(at index: Int) {
        QueuePlaybackActions.playFromHistory(at: index, appEnvironment: appEnvironment)
        navigationCoordinator?.isMiniPlayerQueueSheetPresented = false
        performDismiss()
    }
    #endif
}

#Preview {
    Text("Tap to open")
        .sheet(isPresented: .constant(true)) {
            QueueManagementSheet()
        }
}
