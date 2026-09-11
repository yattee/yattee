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

    /// One row, from whichever history the screen is reading.
    ///
    /// The local entry travels with it rather than being looked up again: it is
    /// what supplies the progress bar and the resume point, and a server row
    /// gets one whenever the same video was also watched on this device.
    private struct HistoryRow: Identifiable {
        let videoID: String
        var video: Video
        var entry: WatchEntry?
        /// Whether `video` is real metadata rather than the standing-in
        /// placeholder a bare server ID starts as.
        var isHydrated: Bool
        /// Whether the metadata fetch was made and could not describe the
        /// video, as opposed to never having been answered yet.
        var metadataFailed = false

        var id: String { videoID }

        /// The video as the row shows it.
        ///
        /// A row whose fetch failed says so instead of standing as its own ID
        /// for the rest of the session, where nothing told a row still loading
        /// apart from a dead one. Only the display changes: `video` — what
        /// plays, and what the queue is handed — is untouched.
        var displayVideo: Video {
            guard metadataFailed, !isHydrated else { return video }
            return .metadataUnavailable(
                for: videoID,
                title: String(localized: "home.history.metadataUnavailable")
            )
        }
    }

    /// The rows on screen, and the same rows' videos beside them.
    ///
    /// The videos are kept as their own array because every row hands the whole
    /// list to the queue: deriving it per row would walk the history once per
    /// visible row instead of once per load.
    @State private var rows: [HistoryRow] = []
    @State private var rowVideos: [Video] = []

    @State private var showingClearConfirmation = false
    @State private var selectedClearOption: ClearHistoryOption?

    // MARK: - Server state

    /// The effective context the rows on screen belong to, so a status change
    /// that does not move it does not force a reload.
    @State private var loadedContext: DataContext?
    /// Which load the state belongs to. Cancelling the previous task is not
    /// enough on its own: a request that already came back races the
    /// cancellation, and its rows would be appended to a history nobody is
    /// looking at any more.
    @State private var loadGeneration = 0
    @State private var loadTask: Task<Void, Never>?
    /// The lowest page still worth asking for; 1-based, like the server's own
    /// numbering.
    ///
    /// Normally the page number comes from the rows themselves. This is the
    /// floor under it, raised past any page that turned out to hold nothing new,
    /// so a page that cannot move the list on is never asked for twice.
    @State private var pageFloor = 1
    @State private var hasMorePages = false
    @State private var isLoadingPage = false
    @State private var serverErrorMessage: String?
    /// Videos a metadata fetch has already been started for, so a row that
    /// scrolls in and out again does not ask twice — including the ones whose
    /// fetch failed, which would otherwise retry on every pass.
    @State private var hydrationAttempted: Set<String> = []
    /// The metadata fetches in flight, by video ID.
    ///
    /// Held on to so a reload can cancel them: without that, switching accounts
    /// mid-scroll leaves a whole load's worth of requests running against an
    /// instance whose history is already off screen, and starts a second set
    /// beside them.
    @State private var hydrationTasks: [String: Task<Void, Never>] = [:]
    /// The rows waiting for a fetch slot, in the order they asked for one.
    @State private var hydrationQueue: [String] = []
    /// Every row that has asked for metadata and has not been given any.
    ///
    /// Unlike ``hydrationAttempted`` this survives a reload, and it is what a
    /// reload owes a fetch to afterwards: the work it cancelled would otherwise
    /// be nobody's to start again.
    @State private var hydrationPending: Set<String> = []
    /// The rows on screen right now.
    ///
    /// A row asks for its metadata as it appears, and that is the only moment
    /// it asks — so an appearance that lands while the account's history is not
    /// what the screen is reading (a status still settling, an instance not yet
    /// arrived) asks for nothing, and nothing would ever ask again. Remembering
    /// what is on screen lets the next load make good on it.
    @State private var visibleRowIDs: Set<String> = []
    /// Which set of fetches the slots belong to.
    ///
    /// Bumped whenever the in-flight fetches are dropped, so a task from before
    /// that cannot free a slot the load after it has since given to a fetch of
    /// the same video.
    @State private var hydrationEpoch = 0

    /// How many IDs one page of server history asks for.
    private static let serverPageSize = 60

    /// How many metadata fetches a load may have in flight at once.
    ///
    /// A page is 60 rows and a search hydrates all of them at once, which
    /// unbounded would be 60 simultaneous requests to a public instance.
    private static let hydrationConcurrency = 6

    /// The page to ask the server for next.
    ///
    /// Read from the rows that are loaded rather than counted up from the last
    /// request, so a deletion — which shifts every server offset after it —
    /// cannot make the next request skip the item that moved back across the
    /// page boundary.
    private var nextServerPage: Int {
        max(
            ServerHistoryPaging.nextPage(loadedRowCount: rows.count, pageSize: Self.serverPageSize),
            pageFloor
        )
    }

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

    // MARK: - Context

    /// The account whose history is on screen, or `nil` when it is the device's.
    ///
    /// The *effective* context, so a selected account that cannot be used right
    /// now shows the local history — with the banner saying why — instead of an
    /// empty list nobody can explain.
    private var contextAccount: Account? {
        guard let appEnvironment,
              case let .account(id) = appEnvironment.dataContextValidator.effectiveContext
        else { return nil }

        return appEnvironment.accountsManager.account(id: id)
    }

    /// Which history the rows, the row actions and the clear menu all belong to.
    ///
    /// Read live rather than stored: it follows the effective context, and the
    /// same value gates every affordance so none of them can be offering an
    /// action against a store the list is not showing.
    private var displayMode: HistoryDisplayMode {
        guard let appEnvironment else { return .local }
        let account = contextAccount

        return HistoryDisplayMode.resolve(
            effectiveContext: appEnvironment.dataContextValidator.effectiveContext,
            account: account,
            capabilities: account.flatMap { appEnvironment.accountsManager.capabilities(for: $0) }
        )
    }

    private var contextUnavailability: DataContextUnavailability? {
        guard appEnvironment?.accountsManager.currentContext.isLocal == false else { return nil }
        return appEnvironment?.dataContextValidator.unavailability
    }

    // MARK: - Rows

    /// History rows filtered by search text.
    private var filteredRows: [HistoryRow] {
        guard !searchText.isEmpty else { return rows }
        let query = searchText.lowercased()
        return rows.filter { row in
            row.video.title.lowercased().contains(query) ||
            row.video.author.name.lowercased().contains(query) ||
            row.videoID.lowercased().contains(query)
        }
    }

    /// The filtered rows' videos, in the same order — what a row hands the queue.
    private var filteredVideos: [Video] {
        guard !searchText.isEmpty else { return rowVideos }
        return filteredRows.map(\.video)
    }

    /// Nothing fetched yet and no reason given — the spinner is for the first
    /// page only, a later page loads under the rows that are already there.
    private var isLoadingFirstServerPage: Bool {
        guard case .server = displayMode else { return false }
        return rows.isEmpty && isLoadingPage
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

    private var viewOptionsSheetContent: some View {
        ViewOptionsSheet(
            layout: $layout,
            rowStyle: $rowStyle,
            gridColumns: $gridColumns,
            hideWatched: nil,  // No hide watched for history view
            maxGridColumns: gridConfig.maxColumns
        )
    }

    /// View options button lives on the leading edge on macOS, trailing elsewhere.
    private var viewOptionsPlacement: ToolbarItemPlacement {
        #if os(macOS)
        .navigation
        #else
        .primaryAction
        #endif
    }

    var body: some View {
        GeometryReader { geometry in
            #if os(tvOS)
            VStack(spacing: 0) {
                // tvOS: Inline search field and action button for better focus navigation
                HStack(spacing: 24) {
                    TextField("search.history.placeholder", text: $searchText)
                        .textFieldStyle(.plain)

                    Button {
                        showViewOptions = true
                    } label: {
                        Label(String(localized: "viewOptions.title"), systemImage: "slider.horizontal.3")
                    }

                    // The server has no clear-all, so this is the device's
                    // history only — the same menu it has always been.
                    if displayMode.isLocal, !rows.isEmpty {
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
                            Label(String(localized: "home.history.clear"), systemImage: "trash")
                        }
                    }

                    DataContextSwitcherButton()
                }
                .focusSection()
                .padding(.horizontal, 48)
                .padding(.top, 20)
                .padding(.bottom, 20)

                // Content
                content
                    .focusSection()
            }
            .onChange(of: geometry.size.width, initial: true) { _, newWidth in
                viewWidth = newWidth
            }
            #else
            content
                .onChange(of: geometry.size.width, initial: true) { _, newWidth in
                    viewWidth = newWidth
                }
            #endif
        }
        // Above the list rather than inside it: the rows are local data while
        // this is showing, and nothing else on screen says so.
        .safeAreaInset(edge: .top, spacing: 0) {
            if let contextUnavailability {
                DataContextUnavailableBanner(reason: contextUnavailability)
            }
        }
        #if !os(tvOS)
        .navigationTitle(String(localized: "home.history.title"))
        .toolbarTitleDisplayMode(.inlineLarge)
        .searchable(text: $searchText, prompt: Text(String(localized: "history.search.placeholder")))
        .toolbar {
            #if os(macOS)
            // Pin the trailing group (search field + toolbar buttons) to the right edge,
            // matching the global Search view.
            if #available(macOS 26, *) {
                ToolbarSpacer(.flexible, placement: .primaryAction)
            }
            #endif
            ToolbarItem(placement: viewOptionsPlacement) {
                DataContextSwitcherMenu()
            }
            // View options button (always visible)
            ToolbarItem(placement: viewOptionsPlacement) {
                Button {
                    showViewOptions = true
                } label: {
                    Label(String(localized: "viewOptions.title"), systemImage: "slider.horizontal.3")
                }
                .liquidGlassTransitionSource(id: "historyViewOptions", in: sheetTransition)
                #if os(macOS)
                .popover(isPresented: $showViewOptions, arrowEdge: .bottom) {
                    viewOptionsSheetContent
                }
                #endif
            }

            // Clear history menu (local history only, and only when not empty):
            // the server offers no way to clear a history in one call.
            if displayMode.isLocal, !rows.isEmpty {
                ToolbarItem(placement: .primaryAction) {
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
        #if !os(macOS)
        .sheet(isPresented: $showViewOptions) {
            viewOptionsSheetContent
                .liquidGlassSheetContent(sourceID: "historyViewOptions", in: sheetTransition)
        }
        #endif
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
        .presentationCompactAdaptation(.sheet)
        .onAppear {
            startLoad()
        }
        .onReceive(NotificationCenter.default.publisher(for: .watchHistoryDidChange)) { _ in
            // The device's own history changed. The account's is the server's to
            // change, and a local write is not news about it.
            if displayMode.isLocal {
                loadHistory()
            }
        }
        // Selecting another account — or local — changes whose history this is,
        // and the previous rows may not be shown for a moment longer.
        //
        // Compared rather than taken on trust: the selection is announced by
        // more than the switcher — a repair, an arriving sync, the first
        // resolution of the stored choice — and most of those settle on the
        // context that is already on screen. Reloading for one of those would
        // throw away rows and half-finished metadata to fetch the same history
        // again.
        .onReceive(NotificationCenter.default.publisher(for: .dataContextDidChange)) { _ in
            reloadIfEffectiveContextMoved()
        }
        // The same, without the context moving: the credential behind the
        // account was replaced, so the history may now be someone else's.
        .onReceive(NotificationCenter.default.publisher(for: .accountCredentialDidChange)) { _ in
            startLoad()
        }
        // A status, an account or an instance changing moves reads between the
        // account and local without the stored context moving at all.
        .onReceive(NotificationCenter.default.publisher(for: .accountStatusesDidChange)) { _ in
            reloadIfEffectiveContextMoved()
        }
        .onReceive(NotificationCenter.default.publisher(for: .accountsDidChange)) { _ in
            reloadIfEffectiveContextMoved()
        }
        .onReceive(NotificationCenter.default.publisher(for: .instancesDidChange)) { _ in
            reloadIfEffectiveContextMoved()
        }
        // Something was just watched and mirrored to the account whose history
        // this is. The server has moved it to the front; so does the list,
        // rather than waiting to be left and come back to.
        .onReceive(NotificationCenter.default.publisher(for: .serverWatchHistoryDidUpdate)) { notification in
            applyServerUpdate(notification)
        }
        // Searching reads titles, and a server row starts with only an ID.
        .onChange(of: searchText) { _, newValue in
            guard !newValue.isEmpty, case let .server(account) = displayMode else { return }
            hydrateAllLoaded(account: account)
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if isLoadingFirstServerPage {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let serverErrorMessage, rows.isEmpty {
            serverErrorView(serverErrorMessage)
        } else if filteredRows.isEmpty {
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

    // MARK: - Empty View

    @ViewBuilder
    private var emptyView: some View {
        if !searchText.isEmpty {
            ContentUnavailableView.search(text: searchText)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ContentUnavailableView {
                Label(String(localized: "home.history.title"), systemImage: "clock")
            } description: {
                Text(String(localized: "home.history.empty"))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func serverErrorView(_ message: String) -> some View {
        ContentUnavailableView {
            Label(String(localized: "history.remote.load.error"), systemImage: "exclamationmark.triangle")
        } description: {
            Text(message)
        } actions: {
            Button(String(localized: "common.retry")) {
                startLoad()
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - List Layout

    private var listContent: some View {
        VideoListContainer(
            listStyle: listStyle,
            rowStyle: rowStyle,
            header: {
                // Header spacer for top padding
                Spacer()
                    .frame(height: 16)
            },
            content: {
                ForEach(Array(filteredRows.enumerated()), id: \.element.id) { index, row in
                    VideoListRow(
                        isLast: index == filteredRows.count - 1,
                        rowStyle: rowStyle,
                        listStyle: listStyle
                    ) {
                        entryRowView(row: row, index: index)
                    }
                    #if !os(tvOS)
                    .videoSwipeActions(
                        video: row.video,
                        fixedActions: [
                            SwipeAction(
                                symbolImage: "trash.fill",
                                tint: .white,
                                background: .red
                            ) { reset in
                                remove(row)
                                reset()
                            }
                        ]
                    )
                    #endif
                }
            },
            footer: {
                loadMoreFooter
            }
        )
    }

    /// The trigger that asks for the next page, and the spinner while it is out.
    ///
    /// Server mode only — the device's history is read in one go and has no
    /// second page to ask for.
    @ViewBuilder
    private var loadMoreFooter: some View {
        if case let .server(account) = displayMode {
            LoadMoreTrigger(isLoading: isLoadingPage, hasMore: hasMorePages) {
                beginPageLoad(nextServerPage, account: account)
            }
        }
    }

    /// Reusable row view for a history entry.
    @ViewBuilder
    private func entryRowView(row: HistoryRow, index: Int) -> some View {
        VideoRowView(
            video: row.displayVideo,
            style: rowStyle,
            watchProgress: row.entry.flatMap { watchProgress(for: $0) },
            customMetadata: remainingMetadata(for: row)
        )
        .tappableVideo(
            row.video,
            startTime: row.entry?.watchedSeconds,
            customActions: rowActions(for: row),
            context: .history,
            queueSource: historyQueueSource,
            sourceLabel: String(localized: "queue.source.history"),
            videoList: filteredVideos,
            videoIndex: index,
            loadMoreVideos: loadMoreHistoryCallback
        )
        .onAppear {
            rowDidAppear(row)
        }
        .onDisappear {
            visibleRowIDs.remove(row.videoID)
        }
    }

    /// What a row offers in its menu: removal always, and a second go at the
    /// metadata for a row that could not be described.
    ///
    /// The retry is the only way back for such a row — a fetch is asked for once
    /// per load, and the instance that failed to answer may well answer now.
    private func rowActions(for row: HistoryRow) -> [VideoContextAction] {
        var actions: [VideoContextAction] = []

        if row.metadataFailed {
            actions.append(
                VideoContextAction(
                    String(localized: "home.history.metadataRetry"),
                    systemImage: "arrow.clockwise",
                    action: { retryHydration(row) }
                )
            )
        }

        actions.append(
            VideoContextAction(
                String(localized: "home.history.remove"),
                systemImage: "trash",
                role: .destructive,
                action: { remove(row) }
            )
        )

        return actions
    }

    /// How much of the video is left, when a local entry knows.
    private func remainingMetadata(for row: HistoryRow) -> String? {
        guard let entry = row.entry, !entry.isFinished, !entry.isLive else { return nil }
        return String(localized: "home.history.remaining \(entry.remainingTime)")
    }

    // MARK: - Grid Layout

    private var gridContent: some View {
        ScrollView {
            VStack(spacing: 0) {
                VideoGridContent(columns: gridConfig.effectiveColumns) {
                    ForEach(Array(filteredRows.enumerated()), id: \.element.id) { index, row in
                        VideoCardView(
                            video: row.displayVideo,
                            watchProgress: row.entry.flatMap { watchProgress(for: $0) },
                            isCompact: gridConfig.isCompactCards
                        )
                        .tappableVideo(
                            row.video,
                            startTime: row.entry?.watchedSeconds,
                            customActions: rowActions(for: row),
                            context: .history,
                            queueSource: historyQueueSource,
                            sourceLabel: String(localized: "queue.source.history"),
                            videoList: filteredVideos,
                            videoIndex: index,
                            loadMoreVideos: loadMoreHistoryCallback
                        )
                        .onAppear {
                            rowDidAppear(row)
                        }
                        .onDisappear {
                            visibleRowIDs.remove(row.videoID)
                        }
                    }
                }

                loadMoreFooter
            }
        }
        #if os(tvOS)
        .scrollClipDisabled()
        #endif
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

    // MARK: - Loading

    private func startLoad() {
        loadTask?.cancel()
        loadTask = nil
        cancelHydration()

        guard let account = beginLoad() else { return }
        beginPageLoad(1, account: account)
    }

    private func reloadIfEffectiveContextMoved() {
        guard appEnvironment?.dataContextValidator.effectiveContext != loadedContext else { return }
        startLoad()
    }

    /// Records which history the rows belong to and reads the local one when
    /// that is what is being shown, returning the account whose pages still have
    /// to be fetched.
    ///
    /// Local data is read synchronously and stays that way: an await before it
    /// would put the empty state on screen for a frame every time this view
    /// appears.
    private func beginLoad() -> Account? {
        guard let appEnvironment else { return nil }

        // Recorded on every load, not only on a context change: the first load
        // of a session has to establish what is on screen, or the first status
        // change would look like a move and reload for nothing.
        let context = appEnvironment.dataContextValidator.effectiveContext
        let movedContext = loadedContext != nil && loadedContext != context

        loadedContext = context
        loadGeneration += 1
        serverErrorMessage = nil
        isLoadingPage = false
        hydrationAttempted.removeAll()
        pageFloor = 1

        // What the rows are owed, and which of them are on screen, only means
        // anything while they are the same rows. Another history's IDs would
        // never match a row again.
        if movedContext {
            hydrationPending.removeAll()
            visibleRowIDs.removeAll()
        }

        guard case let .server(account) = displayMode else {
            hasMorePages = false
            loadHistory()
            return nil
        }

        setRows([])
        hasMorePages = true
        return account
    }

    /// Starts one page fetch, marking the load as in flight before the task is
    /// even scheduled.
    ///
    /// The flag has to be set here rather than inside the task: the trigger at
    /// the end of the list can appear twice before a task body first runs, and
    /// both would ask for the same page.
    private func beginPageLoad(_ page: Int, account: Account) {
        guard !isLoadingPage else { return }

        isLoadingPage = true
        let generation = loadGeneration
        loadTask = Task { await loadPage(page, account: account, generation: generation) }
    }

    private func loadPage(_ page: Int, account: Account, generation: Int) async {
        guard let appEnvironment else { return }

        defer {
            if generation == loadGeneration {
                isLoadingPage = false
            }
        }

        do {
            let ids = try await appEnvironment.accountService.watchHistory(
                page: page,
                maxResults: Self.serverPageSize,
                for: account
            )

            guard generation == loadGeneration else { return }

            let appended = append(ids)

            // A page that held nothing this list did not already have cannot be
            // what moves it on, however many times it is asked for.
            if appended == 0 {
                pageFloor = page + 1
            }

            // A page the server could not fill is the last one there is; so is
            // an empty one, which is what asking past the end returns.
            hasMorePages = ids.count >= Self.serverPageSize

            // A search is matching on titles, and rows that arrived without one
            // would sit out of the results until somebody scrolled them into
            // view — which, being filtered out, they never are.
            if !searchText.isEmpty {
                hydrateAllLoaded(account: account)
            } else {
                // Rows that were already asking for metadata when this load
                // replaced them. They are back, unchanged and still without a
                // title, and nothing is going to announce their appearance a
                // second time.
                resumeHydration(account: account)
            }
        } catch is CancellationError {
            // Another load is taking over — it owns the state now.
        } catch let error as APIError where error == .cancelled {
            // The same, one layer down.
        } catch {
            guard generation == loadGeneration else { return }
            hasMorePages = false
            serverErrorMessage = error.localizedDescription
        }
    }

    /// Appends a page of server IDs, in the order the server gave them.
    ///
    /// Never re-sorted: the server's order *is* the history, newest first, and
    /// the local entries some of these rows have were written at times that say
    /// nothing about when the account watched them.
    /// - Returns: how many of the IDs were rows this list did not already have.
    @discardableResult
    private func append(_ ids: [String]) -> Int {
        var known = Set(rows.map(\.videoID))
        var appended: [HistoryRow] = []

        for id in ids where !known.contains(id) {
            known.insert(id)
            appended.append(makeRow(id: id))
        }

        guard !appended.isEmpty else { return 0 }

        rows.append(contentsOf: appended)
        rowVideos.append(contentsOf: appended.map(\.video))
        return appended.count
    }

    /// A row for one server-side ID, from local data where there is some.
    ///
    /// A video watched on this device is already known — title, thumbnail,
    /// progress and all — so the row is complete before anything is fetched.
    /// Everything else starts as a placeholder and is filled in as it appears.
    private func makeRow(id: String) -> HistoryRow {
        if let entry = dataManager?.watchEntry(for: id) {
            return HistoryRow(videoID: id, video: entry.toVideo(), entry: entry, isHydrated: true)
        }

        // The entry is never dropped for want of a title: the account watched
        // this video, and a history missing rows it cannot describe is a wrong
        // history.
        return HistoryRow(videoID: id, video: .metadataPlaceholder(for: id), entry: nil, isHydrated: false)
    }

    // MARK: - Hydration

    /// A row came on screen: it is noted as visible, and asks for its metadata.
    private func rowDidAppear(_ row: HistoryRow) {
        visibleRowIDs.insert(row.videoID)

        guard case let .server(account) = displayMode else { return }
        hydrate(row, account: account)
    }

    /// Fetches metadata for every loaded row that has none, whether or not it is
    /// on screen.
    ///
    /// For searching, which reads titles: a row still standing as its own video
    /// ID matches nothing anybody would type, and the usual trigger — the row
    /// appearing — cannot fire for a row the search has filtered out. Bounded by
    /// what is loaded, and each row is still only ever asked for once.
    private func hydrateAllLoaded(account: Account) {
        for row in rows where !row.isHydrated {
            hydrate(row, account: account)
        }
    }

    /// Makes good on the rows a load left without metadata.
    ///
    /// The ones whose fetch the reload cancelled, and the ones on screen that
    /// never got to ask — a row appearing is the only thing that asks, and an
    /// appearance during a moment when this was not the account's history at
    /// all asks for nothing. Bounded by what has actually been looked at, and
    /// each row is still only ever fetched once per load.
    private func resumeHydration(account: Account) {
        for row in rows
        where !row.isHydrated
            && (hydrationPending.contains(row.videoID) || visibleRowIDs.contains(row.videoID)) {
            hydrate(row, account: account)
        }
    }

    /// Asks again for a row the instance could not describe.
    ///
    /// A fetch is only ever made once per row per load, so a row that failed has
    /// nothing left that would ask for it. The failure is lifted first: the row
    /// goes back to reading as one still being fetched, which is what it is.
    private func retryHydration(_ row: HistoryRow) {
        guard case let .server(account) = displayMode else { return }

        hydrationAttempted.remove(row.videoID)

        if let index = rows.firstIndex(where: { $0.videoID == row.videoID }) {
            rows[index].metadataFailed = false
        }

        hydrate(row, account: account)
    }

    /// Asks for one row's metadata, as the row appears.
    ///
    /// The request itself waits its turn: the row joins the queue, and the
    /// fetches are started a few at a time from there.
    private func hydrate(_ row: HistoryRow, account: Account) {
        guard !row.isHydrated,
              !hydrationAttempted.contains(row.videoID),
              let appEnvironment,
              appEnvironment.accountsManager.instance(for: account) != nil
        else { return }

        hydrationAttempted.insert(row.videoID)
        hydrationPending.insert(row.videoID)
        hydrationQueue.append(row.videoID)
        pumpHydration(account: account)
    }

    /// Starts as many queued fetches as there are free slots.
    ///
    /// Through the account's own instance: every ID the server returns is a
    /// YouTube ID, and the account's instance is the one that has it.
    private func pumpHydration(account: Account) {
        guard let appEnvironment,
              let instance = appEnvironment.accountsManager.instance(for: account)
        else { return }

        let epoch = hydrationEpoch
        let accountID = account.id

        while hydrationTasks.count < Self.hydrationConcurrency, !hydrationQueue.isEmpty {
            let videoID = hydrationQueue.removeFirst()

            hydrationTasks[videoID] = Task {
                do {
                    let video = try await appEnvironment.contentService.video(id: videoID, instance: instance)
                    // Whose history this describes is what decides whether it
                    // may be shown — not which load asked for it. A reload of
                    // the same account puts the same rows back, and metadata
                    // fetched for one of them is still that row's metadata.
                    if isShowing(accountID: accountID) {
                        apply(video, to: videoID)
                    }
                } catch is CancellationError {
                    // A reload took the fetch over; the row is its to ask for.
                } catch let error as APIError where error == .cancelled {
                    // The same, one layer down.
                } catch {
                    // The row stays — a video the account watched is part of its
                    // history whether or not this instance can describe it — but
                    // it says it could not be described rather than standing as
                    // its own ID with nothing to tell it from one still loading.
                    if isShowing(accountID: accountID) {
                        markMetadataUnavailable(videoID)
                    }
                }

                // A finished fetch frees its slot for the next row — but only
                // among the fetches it started with. A later set has already
                // emptied this queue and started its own, and giving back a
                // slot there would drop a task that is still running.
                guard epoch == hydrationEpoch else { return }
                hydrationTasks[videoID] = nil
                pumpHydration(account: account)
            }
        }
    }

    /// Whether the rows on screen are still that account's history.
    private func isShowing(accountID: UUID) -> Bool {
        guard case let .server(account) = displayMode else { return false }
        return account.id == accountID
    }

    /// Drops everything the current load was still going to fetch, and stops
    /// what it had already started.
    private func cancelHydration() {
        for task in hydrationTasks.values {
            task.cancel()
        }

        hydrationTasks.removeAll()
        hydrationQueue.removeAll()
        hydrationEpoch += 1
    }

    private func apply(_ video: Video, to videoID: String) {
        hydrationPending.remove(videoID)

        guard let index = rows.firstIndex(where: { $0.videoID == videoID }) else { return }

        rows[index].video = video
        rows[index].isHydrated = true
        rows[index].metadataFailed = false

        if rowVideos.indices.contains(index) {
            rowVideos[index] = video
        }
    }

    /// Marks a row the instance could not describe.
    ///
    /// It stays pending, so a reload owes it another fetch on its own; what
    /// changes is that until one succeeds the row says it has no metadata
    /// rather than showing the video ID as if it were a title.
    private func markMetadataUnavailable(_ videoID: String) {
        guard let index = rows.firstIndex(where: { $0.videoID == videoID }) else { return }
        rows[index].metadataFailed = true
    }

    // MARK: - Live updates

    /// Moves a video that was just recorded on the server to the front of the
    /// list.
    ///
    /// Only for the account the rows on screen were loaded for — `loadedContext`
    /// rather than the live one, which is the same guard the generation gives an
    /// awaited result: a post that lands as the context moves belongs to the
    /// history that is on its way out, not the one arriving.
    private func applyServerUpdate(_ notification: Notification) {
        guard case let .server(account) = displayMode,
              let accountID = notification.userInfo?[ServerWatchHistoryUpdate.accountIDKey] as? UUID,
              accountID == account.id,
              loadedContext == .account(accountID),
              let videoID = notification.userInfo?[ServerWatchHistoryUpdate.videoIDKey] as? String
        else { return }

        bumpToFront(videoID)
    }

    /// Puts a video at the top of the rows, wherever it was — or was not.
    ///
    /// What the server does with a repeated post: the video moves to the front
    /// of the history rather than appearing twice in it. A video not among the
    /// loaded rows is new to the front of the list, and arrives with whatever
    /// the device already knows about it, which for something just watched here
    /// is everything.
    private func bumpToFront(_ videoID: String) {
        if let index = rows.firstIndex(where: { $0.videoID == videoID }) {
            guard index != 0 else { return }
            rows.insert(rows.remove(at: index), at: 0)
        } else {
            rows.insert(makeRow(id: videoID), at: 0)
        }

        rowVideos = rows.map(\.video)
    }

    // MARK: - Reading

    private func loadHistory() {
        let entries = dataManager?.watchHistory(limit: 10000) ?? []
        setRows(entries.map { HistoryRow(videoID: $0.videoID, video: $0.toVideo(), entry: $0, isHydrated: true) })
    }

    private func setRows(_ newRows: [HistoryRow]) {
        rows = newRows
        rowVideos = newRows.map(\.video)
    }

    // MARK: - Removing

    private func remove(_ row: HistoryRow) {
        switch displayMode {
        case .local:
            dataManager?.removeFromHistory(videoID: row.videoID)
            loadHistory()

        case let .server(account):
            removeFromServer(row.videoID, account: account)
        }
    }

    /// Removes one video from the account's server history, and from the rows.
    ///
    /// The server's history only — the local ``WatchEntry`` behind the row, if
    /// there is one, is the device's own record and is cleared from the local
    /// history view.
    private func removeFromServer(_ videoID: String, account: Account) {
        guard let appEnvironment else { return }

        let generation = loadGeneration

        Task {
            do {
                try await appEnvironment.accountService.removeFromWatchHistory(videoID: videoID, for: account)

                // The rows may belong to another account by now; the removal
                // still happened, but this list is not the one to take it out of.
                guard generation == loadGeneration else { return }

                // Accepted: a watch finishing at the same moment can post this
                // same video after the server took the delete, and this
                // completion — arriving later than the order the server saw —
                // then takes out a row the server still has. The list is wrong
                // only until the next load reads the account's history again.
                removeRow(videoID)
            } catch {
                appEnvironment.toastManager.showError(
                    String(localized: "history.remote.delete.error"),
                    subtitle: error.localizedDescription
                )
            }
        }
    }

    private func removeRow(_ videoID: String) {
        rows.removeAll { $0.videoID == videoID }
        rowVideos = rows.map(\.video)
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
