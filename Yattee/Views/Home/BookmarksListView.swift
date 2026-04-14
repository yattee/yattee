//
//  BookmarksListView.swift
//  Yattee
//
//  Full page view for bookmarked videos.
//

import SwiftUI

struct BookmarksListView: View {
    @Environment(\.appEnvironment) private var appEnvironment
    @Namespace private var sheetTransition
    @State private var bookmarks: [Bookmark] = []

    // View options (persisted)
    @AppStorage("bookmarks.layout") private var layout: VideoListLayout = .list
    @AppStorage("bookmarks.rowStyle") private var rowStyle: VideoRowStyle = .regular
    @AppStorage("bookmarks.gridColumns") private var gridColumns = 2
    @AppStorage("bookmarks.hideWatched") private var hideWatched = false

    /// List style from centralized settings.
    private var listStyle: VideoListStyle {
        appEnvironment?.settingsManager.listStyle ?? .inset
    }

    // UI state
    @State private var showViewOptions = false
    @State private var viewWidth: CGFloat = 0
    @State private var watchEntriesMap: [String: WatchEntry] = [:]
    @State private var searchText = ""

    // Grid layout configuration
    private var gridConfig: GridLayoutConfiguration {
        GridLayoutConfiguration(viewWidth: viewWidth, gridColumns: gridColumns)
    }

    private var dataManager: DataManager? { appEnvironment?.dataManager }

    /// Bookmarks filtered by search and watch status.
    private var filteredBookmarks: [Bookmark] {
        var result = bookmarks

        // Apply search filter
        if !searchText.isEmpty {
            let query = searchText.lowercased()
            result = result.filter { bookmark in
                bookmark.title.lowercased().contains(query) ||
                bookmark.authorName.lowercased().contains(query) ||
                bookmark.videoID.lowercased().contains(query) ||
                bookmark.tags.contains { $0.lowercased().contains(query) } ||
                (bookmark.note?.lowercased().contains(query) ?? false)
            }
        }

        // Apply watch status filter
        if hideWatched {
            result = result.filter { bookmark in
                guard let entry = watchEntriesMap[bookmark.videoID] else { return true }
                return !entry.isFinished
            }
        }

        return result
    }

    /// Gets the watch progress (0.0-1.0) for a bookmark, or nil if not watched/finished.
    private func watchProgress(for bookmark: Bookmark) -> Double? {
        guard let entry = watchEntriesMap[bookmark.videoID] else { return nil }
        let progress = entry.progress
        // Only show progress bar for partially watched videos
        return progress > 0 && progress < 1 ? progress : nil
    }

    /// Queue source for bookmarks.
    private var bookmarksQueueSource: QueueSource {
        .manual
    }

    /// Stub callback for video queue continuation.
    @Sendable
    private func loadMoreBookmarksCallback() async throws -> ([Video], String?) {
        return ([], nil)
    }

    var body: some View {
        GeometryReader { geometry in
            #if os(tvOS)
            VStack(spacing: 0) {
                // tvOS: Inline search field and action button for better focus navigation
                HStack(spacing: 24) {
                    TextField("search.bookmarks.placeholder", text: $searchText)
                        .textFieldStyle(.plain)

                    Button {
                        showViewOptions = true
                    } label: {
                        Label(String(localized: "viewOptions.title"), systemImage: "slider.horizontal.3")
                    }
                }
                .focusSection()
                .padding(.horizontal, 48)
                .padding(.top, 80)

                // Content
                Group {
                    if filteredBookmarks.isEmpty {
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
                if filteredBookmarks.isEmpty {
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
            .onChange(of: geometry.size.width, initial: true) { _, newWidth in
                viewWidth = newWidth
            }
            #endif
        }
        #if !os(tvOS)
        .navigationTitle(String(localized: "home.bookmarks.title"))
        .toolbarTitleDisplayMode(.inlineLarge)
        .searchable(text: $searchText, prompt: Text(String(localized: "bookmarks.search.placeholder")))
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showViewOptions = true
                } label: {
                    Label(String(localized: "viewOptions.title"), systemImage: "slider.horizontal.3")
                }
                .liquidGlassTransitionSource(id: "bookmarksViewOptions", in: sheetTransition)
            }
        }
        #endif
        .sheet(isPresented: $showViewOptions) {
            ViewOptionsSheet(
                layout: $layout,
                rowStyle: $rowStyle,
                gridColumns: $gridColumns,
                hideWatched: $hideWatched,
                maxGridColumns: gridConfig.maxColumns
            )
            .liquidGlassSheetContent(sourceID: "bookmarksViewOptions", in: sheetTransition)
        }
        .onAppear {
            loadBookmarks()
            loadWatchEntries()
        }
        .onReceive(NotificationCenter.default.publisher(for: .bookmarksDidChange)) { _ in
            loadBookmarks()
        }
        .onReceive(NotificationCenter.default.publisher(for: .watchHistoryDidChange)) { _ in
            loadWatchEntries()
        }
    }

    // MARK: - Empty View

    @ViewBuilder
    private var emptyView: some View {
        if !searchText.isEmpty {
            ContentUnavailableView.search(text: searchText)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ContentUnavailableView {
                Label(String(localized: "home.bookmarks.title"), systemImage: "bookmark")
            } description: {
                Text(String(localized: "home.bookmarks.empty"))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - List Layout

    private var listContent: some View {
        VideoListContainer(listStyle: listStyle, rowStyle: rowStyle) {
            Spacer()
                .frame(height: 16)
        } content: {
            ForEach(Array(filteredBookmarks.enumerated()), id: \.element.videoID) { index, bookmark in
                VideoListRow(
                    isLast: index == filteredBookmarks.count - 1,
                    rowStyle: rowStyle,
                    listStyle: listStyle
                ) {
                    bookmarkRow(bookmark: bookmark, index: index)
                }
                #if !os(tvOS)
                .videoSwipeActions(
                    video: bookmark.toVideo(),
                    fixedActions: [
                        SwipeAction(
                            symbolImage: "trash.fill",
                            tint: .white,
                            background: .red
                        ) { reset in
                            removeBookmark(bookmark)
                            reset()
                        }
                    ]
                )
                #endif
            }
        }
    }

    // MARK: - Grid Layout

    private var gridContent: some View {
        ScrollView {
            VideoGridContent(columns: gridConfig.effectiveColumns) {
                ForEach(Array(filteredBookmarks.enumerated()), id: \.element.videoID) { index, bookmark in
                    BookmarkCardView(
                        bookmark: bookmark,
                        watchProgress: watchProgress(for: bookmark),
                        isCompact: gridConfig.isCompactCards
                    )
                    .tappableVideo(
                        bookmark.toVideo(),
                        queueSource: bookmarksQueueSource,
                        sourceLabel: String(localized: "queue.source.bookmarks"),
                        videoList: filteredBookmarks.map { $0.toVideo() },
                        videoIndex: index,
                        loadMoreVideos: loadMoreBookmarksCallback
                    )
                    .videoContextMenu(
                        video: bookmark.toVideo(),
                        customActions: [
                            VideoContextAction(
                                String(localized: "home.bookmarks.remove"),
                                systemImage: "trash",
                                role: .destructive,
                                action: { removeBookmark(bookmark) }
                            )
                        ],
                        context: .bookmarks
                    )
                }
            }
        }
    }

    // MARK: - Helper Views

    @ViewBuilder
    private func bookmarkRow(bookmark: Bookmark, index: Int) -> some View {
        BookmarkRowView(
            bookmark: bookmark,
            style: rowStyle,
            watchProgress: watchProgress(for: bookmark),
            onRemove: { removeBookmark(bookmark) },
            queueSource: bookmarksQueueSource,
            sourceLabel: String(localized: "queue.source.bookmarks"),
            videoList: filteredBookmarks.map { $0.toVideo() },
            videoIndex: index,
            loadMoreVideos: loadMoreBookmarksCallback
        )
    }

    private func loadBookmarks() {
        bookmarks = dataManager?.bookmarks(limit: 10000) ?? []
    }

    private func loadWatchEntries() {
        watchEntriesMap = dataManager?.watchEntriesMap() ?? [:]
    }

    private func removeBookmark(_ bookmark: Bookmark) {
        dataManager?.removeBookmark(for: bookmark.videoID)
        loadBookmarks()
    }
}
