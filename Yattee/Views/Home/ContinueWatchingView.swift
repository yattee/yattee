//
//  ContinueWatchingView.swift
//  Yattee
//
//  Full-screen view of all videos in progress.
//

import SwiftUI

struct ContinueWatchingView: View {
    @Environment(\.appEnvironment) private var appEnvironment
    @Namespace private var sheetTransition
    @State private var watchHistory: [WatchEntry] = []

    // View options (persisted)
    @AppStorage("continueWatching.layout") private var layout: VideoListLayout = .grid
    @AppStorage("continueWatching.rowStyle") private var rowStyle: VideoRowStyle = .regular
    @AppStorage("continueWatching.gridColumns") private var gridColumns = 2

    /// List style from centralized settings.
    private var listStyle: VideoListStyle {
        appEnvironment?.settingsManager.listStyle ?? .inset
    }

    // UI state
    @State private var showViewOptions = false
    @State private var viewWidth: CGFloat = 0

    private var dataManager: DataManager? { appEnvironment?.dataManager }

    /// Filtered to only show in-progress videos.
    private var inProgressEntries: [WatchEntry] {
        watchHistory.filter { !$0.isFinished && $0.watchedSeconds > 10 }
    }

    // Grid layout configuration
    private var gridConfig: GridLayoutConfiguration {
        GridLayoutConfiguration(viewWidth: viewWidth, gridColumns: gridColumns)
    }

    var body: some View {
        GeometryReader { geometry in
            Group {
                if inProgressEntries.isEmpty {
                    emptyState
                } else {
                    switch layout {
                    case .list:
                        listContent
                    case .grid:
                        gridContent
                    }
                }
            }
            .onChange(of: geometry.size.width, initial: true) { _, newWidth in
                viewWidth = newWidth
            }
        }
        .navigationTitle(String(localized: "home.continueWatching.title"))
        #if !os(tvOS)
        .toolbarTitleDisplayMode(.inlineLarge)
        #endif
        .toolbar {
            if !inProgressEntries.isEmpty {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showViewOptions = true
                    } label: {
                        Label(String(localized: "viewOptions.title"), systemImage: "slider.horizontal.3")
                    }
                    .liquidGlassTransitionSource(id: "continueWatchingViewOptions", in: sheetTransition)
                }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button(role: .destructive) {
                            clearAllProgress()
                        } label: {
                            Label(String(localized: "continueWatching.clearAll"), systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
        .sheet(isPresented: $showViewOptions) {
            ViewOptionsSheet(
                layout: $layout,
                rowStyle: $rowStyle,
                gridColumns: $gridColumns,
                maxGridColumns: gridConfig.maxColumns
            )
            .liquidGlassSheetContent(sourceID: "continueWatchingViewOptions", in: sheetTransition)
        }
        .onAppear {
            loadHistory()
        }
        .onReceive(NotificationCenter.default.publisher(for: .watchHistoryDidChange)) { _ in
            loadHistory()
        }
    }

    // MARK: - Content

    private var emptyState: some View {
        ContentUnavailableView {
            Label(String(localized: "home.continueWatching.title"), systemImage: "play.circle")
        } description: {
            Text(String(localized: "home.continueWatching.empty"))
        }
    }

    private var listContent: some View {
        VideoListContainer(listStyle: listStyle, rowStyle: rowStyle) {
            // Header spacer for top padding
            Spacer()
                .frame(height: 16)
        } content: {
            ForEach(Array(inProgressEntries.enumerated()), id: \.element.videoID) { index, entry in
                VideoListRow(
                    isLast: index == inProgressEntries.count - 1,
                    rowStyle: rowStyle,
                    listStyle: listStyle
                ) {
                    entryRowView(entry: entry, index: index)
                }
                #if !os(tvOS)
                .videoSwipeActions(
                    video: entry.toVideo(),
                    fixedActions: [
                        SwipeAction(
                            symbolImage: "xmark.circle.fill",
                            tint: .white,
                            background: .red
                        ) { reset in
                            removeEntry(entry)
                            reset()
                        }
                    ]
                )
                #endif
            }
        }
    }

    /// Reusable row view for a watch entry.
    @ViewBuilder
    private func entryRowView(entry: WatchEntry, index: Int) -> some View {
        VideoRowView(
            video: entry.toVideo(),
            style: rowStyle,
            watchProgress: entry.progress,
            customMetadata: entry.isFinished ? nil : String(localized: "home.history.remaining \(entry.remainingTime)")
        )
        .tappableVideo(
            entry.toVideo(),
            startTime: entry.watchedSeconds,
            queueSource: .manual,
            sourceLabel: String(localized: "queue.source.continueWatching"),
            videoList: inProgressEntries.map { $0.toVideo() },
            videoIndex: index,
            loadMoreVideos: loadMoreCallback
        )
        .videoContextMenu(
            video: entry.toVideo(),
            customActions: [
                VideoContextAction(
                    String(localized: "continueWatching.remove"),
                    systemImage: "xmark.circle",
                    role: .destructive,
                    action: { removeEntry(entry) }
                )
            ],
            context: .continueWatching,
            startTime: entry.watchedSeconds
        )
    }

    private var gridContent: some View {
        ScrollView {
            VideoGridContent(columns: gridConfig.effectiveColumns) {
                ForEach(inProgressEntries, id: \.videoID) { entry in
                    TappableContinueWatchingGridCard(entry: entry, onRemove: {
                        removeEntry(entry)
                    })
                }
            }
        }
    }

    // MARK: - Actions

    private func loadHistory() {
        watchHistory = dataManager?.watchHistory(limit: 100) ?? []
    }

    private func removeEntry(_ entry: WatchEntry) {
        dataManager?.removeFromHistory(videoID: entry.videoID)
        loadHistory()
    }

    private func clearAllProgress() {
        dataManager?.clearInProgressHistory()
    }

    /// Stub callback for video queue continuation.
    @Sendable
    private func loadMoreCallback() async throws -> ([Video], String?) {
        return ([], nil)  // No pagination
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        ContinueWatchingView()
    }
    .appEnvironment(.preview)
}
