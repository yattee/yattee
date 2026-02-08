//
//  HistoryListView.swift
//  Yattee
//
//  Full page view for watch history.
//

import SwiftUI

struct HistoryListView: View {
    @Environment(\.appEnvironment) private var appEnvironment
    @Namespace private var sheetTransition
    @State private var history: [WatchEntry] = []
    @State private var videos: [Video] = []  // Cached Video conversions to avoid repeated toVideo() calls
    @State private var showingClearConfirmation = false
    @State private var selectedClearOption: ClearHistoryOption?

    // View options (persisted)
    @AppStorage("history.layout") private var layout: VideoListLayout = .list
    @AppStorage("history.rowStyle") private var rowStyle: VideoRowStyle = .regular
    @AppStorage("history.gridColumns") private var gridColumns = 2

    /// List style from centralized settings.
    private var listStyle: VideoListStyle {
        appEnvironment?.settingsManager.listStyle ?? .inset
    }

    // UI state
    @State private var showViewOptions = false
    @State private var viewWidth: CGFloat = 0
    @State private var searchText = ""

    // Grid layout configuration
    private var gridConfig: GridLayoutConfiguration {
        GridLayoutConfiguration(viewWidth: viewWidth, gridColumns: gridColumns)
    }

    private var dataManager: DataManager? { appEnvironment?.dataManager }

    /// History entries filtered by search text.
    private var filteredHistory: [WatchEntry] {
        guard !searchText.isEmpty else { return history }
        let query = searchText.lowercased()
        return history.filter { entry in
            entry.title.lowercased().contains(query) ||
            entry.authorName.lowercased().contains(query) ||
            entry.videoID.lowercased().contains(query)
        }
    }

    /// Pre-computed Video objects for filtered history entries.
    private var filteredVideos: [Video] {
        guard !searchText.isEmpty else { return videos }
        let filteredIDs = Set(filteredHistory.map { $0.videoID })
        return zip(history, videos)
            .filter { filteredIDs.contains($0.0.videoID) }
            .map { $0.1 }
    }

    /// Gets the watch progress (0.0-1.0) for a watch entry, or nil if finished.
    private func watchProgress(for entry: WatchEntry) -> Double? {
        let progress = entry.progress
        // Only show progress bar for partially watched videos
        return progress > 0 && progress < 1 ? progress : nil
    }

    /// Queue source for history.
    private var historyQueueSource: QueueSource {
        .manual
    }

    /// Stub callback for video queue continuation.
    /// History doesn't support server-side pagination,
    /// so this returns empty to prevent errors.
    @Sendable
    private func loadMoreHistoryCallback() async throws -> ([Video], String?) {
        // History is fully loaded on initial fetch
        // No pagination support available
        return ([], nil)
    }

    var body: some View {
        GeometryReader { geometry in
            #if os(tvOS)
            VStack(spacing: 0) {
                // tvOS: Inline search field and action button for better focus navigation
                HStack(spacing: 24) {
                    TextField("Search history", text: $searchText)
                        .textFieldStyle(.plain)

                    Button {
                        showViewOptions = true
                    } label: {
                        Label(String(localized: "viewOptions.title"), systemImage: "slider.horizontal.3")
                    }
                }
                .focusSection()
                .padding(.horizontal, 48)
                .padding(.top, 20)

                // Content
                Group {
                    if filteredHistory.isEmpty {
                        emptyView
                    } else {
                        switch layout {
                        case .list:
                            listContent
                        case .grid:
                            gridContent
                        }
                    }
                }
                .focusSection()
            }
            .onChange(of: geometry.size.width, initial: true) { _, newWidth in
                viewWidth = newWidth
            }
            #else
            Group {
                if filteredHistory.isEmpty {
                    // Empty state
                    emptyView
                } else {
                    // Content based on layout
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
            #endif
        }
        .navigationTitle(String(localized: "home.history.title"))
        #if !os(tvOS)
        .toolbarTitleDisplayMode(.inlineLarge)
        .searchable(text: $searchText, prompt: Text("Search history"))
        .toolbar {
            // View options button (always visible)
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showViewOptions = true
                } label: {
                    Label(String(localized: "viewOptions.title"), systemImage: "slider.horizontal.3")
                }
                .liquidGlassTransitionSource(id: "historyViewOptions", in: sheetTransition)
            }

            // Clear history menu (only when not empty)
            if !history.isEmpty {
                ToolbarItem(placement: .automatic) {
                    Menu {
                        ForEach(ClearHistoryOption.allCases, id: \.self) { option in
                            Button(role: .destructive) {
                                selectedClearOption = option
                                showingClearConfirmation = true
                            } label: {
                                Label(option.localizedTitle, systemImage: option.systemImage)
                            }
                        }
                    } label: {
                        Image(systemName: "trash")
                    }
                }
            }
        }
        #endif
        .sheet(isPresented: $showViewOptions) {
            ViewOptionsSheet(
                layout: $layout,
                rowStyle: $rowStyle,
                gridColumns: $gridColumns,
                hideWatched: nil,  // No hide watched for history view
                maxGridColumns: gridConfig.maxColumns
            )
            .liquidGlassSheetContent(sourceID: "historyViewOptions", in: sheetTransition)
        }
        .confirmationDialog(
            confirmationTitle,
            isPresented: $showingClearConfirmation,
            titleVisibility: .visible
        ) {
            Button(String(localized: "home.history.clear"), role: .destructive) {
                clearHistory()
            }
            Button(String(localized: "common.cancel"), role: .cancel) {
                selectedClearOption = nil
            }
        }
        .onAppear {
            loadHistory()
        }
        .onReceive(NotificationCenter.default.publisher(for: .watchHistoryDidChange)) { _ in
            loadHistory()
        }
    }

    // MARK: - Empty View

    @ViewBuilder
    private var emptyView: some View {
        if !searchText.isEmpty {
            ContentUnavailableView.search(text: searchText)
        } else {
            ContentUnavailableView {
                Label(String(localized: "home.history.title"), systemImage: "clock")
            } description: {
                Text(String(localized: "home.history.empty"))
            }
        }
    }

    // MARK: - List Layout

    private var listContent: some View {
        VideoListContainer(listStyle: listStyle, rowStyle: rowStyle) {
            // Header spacer for top padding
            Spacer()
                .frame(height: 16)
        } content: {
            ForEach(Array(filteredHistory.enumerated()), id: \.element.videoID) { index, entry in
                let video = filteredVideos[index]
                VideoListRow(
                    isLast: index == filteredHistory.count - 1,
                    rowStyle: rowStyle,
                    listStyle: listStyle
                ) {
                    entryRowView(entry: entry, index: index)
                }
                #if !os(tvOS)
                .videoSwipeActions(
                    video: video,
                    fixedActions: [
                        SwipeAction(
                            symbolImage: "trash.fill",
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

    /// Reusable row view for a history entry.
    @ViewBuilder
    private func entryRowView(entry: WatchEntry, index: Int) -> some View {
        let video = filteredVideos[index]
        VideoRowView(
            video: video,
            style: rowStyle,
            watchProgress: watchProgress(for: entry),
            customMetadata: entry.isFinished ? nil : String(localized: "home.history.remaining \(entry.remainingTime)")
        )
        .tappableVideo(
            video,
            startTime: entry.watchedSeconds,
            customActions: [
                VideoContextAction(
                    String(localized: "home.history.remove"),
                    systemImage: "trash",
                    role: .destructive,
                    action: { removeEntry(entry) }
                )
            ],
            context: .history,
            queueSource: historyQueueSource,
            sourceLabel: String(localized: "queue.source.history"),
            videoList: filteredVideos,
            videoIndex: index,
            loadMoreVideos: loadMoreHistoryCallback
        )
    }

    // MARK: - Grid Layout

    private var gridContent: some View {
        ScrollView {
            VideoGridContent(columns: gridConfig.effectiveColumns) {
                ForEach(Array(filteredHistory.enumerated()), id: \.element.videoID) { index, entry in
                    let video = filteredVideos[index]
                    VideoCardView(
                        video: video,
                        watchProgress: watchProgress(for: entry),
                        isCompact: gridConfig.isCompactCards
                    )
                    .tappableVideo(
                        video,
                        startTime: entry.watchedSeconds,
                        customActions: [
                            VideoContextAction(
                                String(localized: "home.history.remove"),
                                systemImage: "trash",
                                role: .destructive,
                                action: { removeEntry(entry) }
                            )
                        ],
                        context: .history,
                        queueSource: historyQueueSource,
                        sourceLabel: String(localized: "queue.source.history"),
                        videoList: filteredVideos,
                        videoIndex: index,
                        loadMoreVideos: loadMoreHistoryCallback
                    )
                }
            }
        }
    }

    private var confirmationTitle: String {
        guard let option = selectedClearOption else {
            return String(localized: "home.history.clear.confirm")
        }

        if option == .all {
            return String(localized: "home.history.clear.confirm")
        }

        return String(localized: "home.history.clear.confirm.timeRange \(option.localizedTitle)")
    }

    private func loadHistory() {
        history = dataManager?.watchHistory(limit: 10000) ?? []
        videos = history.map { $0.toVideo() }  // Pre-compute all Video conversions once
    }

    private func removeEntry(_ entry: WatchEntry) {
        dataManager?.removeFromHistory(videoID: entry.videoID)
        loadHistory()
    }

    private func clearHistory() {
        guard let option = selectedClearOption else { return }

        if option == .all {
            dataManager?.clearWatchHistory()
        } else if let date = option.cutoffDate {
            dataManager?.clearWatchHistory(since: date)
        }

        selectedClearOption = nil
        loadHistory()
    }
}

// MARK: - Clear History Options

private enum ClearHistoryOption: CaseIterable {
    case lastHour
    case lastDay
    case lastWeek
    case lastMonth
    case all

    var localizedTitle: String {
        switch self {
        case .lastHour:
            return String(localized: "home.history.clear.lastHour")
        case .lastDay:
            return String(localized: "home.history.clear.lastDay")
        case .lastWeek:
            return String(localized: "home.history.clear.lastWeek")
        case .lastMonth:
            return String(localized: "home.history.clear.lastMonth")
        case .all:
            return String(localized: "home.history.clear.all")
        }
    }

    var systemImage: String {
        switch self {
        case .lastHour:
            return "clock"
        case .lastDay:
            return "sun.max"
        case .lastWeek:
            return "calendar"
        case .lastMonth:
            return "calendar.badge.clock"
        case .all:
            return "trash"
        }
    }

    var cutoffDate: Date? {
        let calendar = Calendar.current
        let now = Date()

        switch self {
        case .lastHour:
            return calendar.date(byAdding: .hour, value: -1, to: now)
        case .lastDay:
            return calendar.date(byAdding: .day, value: -1, to: now)
        case .lastWeek:
            return calendar.date(byAdding: .weekOfYear, value: -1, to: now)
        case .lastMonth:
            return calendar.date(byAdding: .month, value: -1, to: now)
        case .all:
            return nil
        }
    }
}
