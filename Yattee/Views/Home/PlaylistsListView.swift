//
//  PlaylistsListView.swift
//  Yattee
//
//  Full page view for listing all playlists.
//

import SwiftUI

struct PlaylistsListView: View {
    @Environment(\.appEnvironment) private var appEnvironment
    @Namespace private var sheetTransition
    @State private var localPlaylists: [LocalPlaylist] = []
    @State private var searchText = ""
    @State private var playlistToEdit: LocalPlaylist?
    #if os(tvOS)
    @FocusState private var focusedPlaylistID: PlaylistListItemID?
    @State private var didSetInitialFocus = false
    #endif

    // MARK: - Remote state

    /// The creation being collected, and where it goes — captured when the
    /// button was pressed.
    ///
    /// The destination travels with the presentation instead of standing beside
    /// it in a second `@State`: a companion value is read by the sheet's own
    /// closure one update behind the button that set it, so a creation on an
    /// account took the local branch — writing to the device and losing the
    /// visibility picker on the way.
    @State private var creation: PlaylistCreationTarget?
    @State private var remoteEdit: RemotePlaylistEdit?
    @State private var remoteDeletion: RemotePlaylistDeletion?
    /// Why the account's list could not be fetched, when it could not.
    @State private var remoteErrorMessage: String?
    /// The effective context the rows on screen belong to, so a status change
    /// that does not move it does not force a reload.
    @State private var loadedContext: DataContext?
    /// Which load the state belongs to. Cancelling the previous task is not
    /// enough on its own: a request that already came back races the
    /// cancellation, and its failure would be reported for a context nobody is
    /// looking at any more.
    @State private var loadGeneration = 0
    @State private var loadTask: Task<Void, Never>?

    /// A form opened over a server-side playlist, filled from the refetch that
    /// preceded it rather than from the row that was tapped.
    private struct RemotePlaylistEdit: Identifiable {
        let id = UUID()
        let account: Account
        let playlistID: String
        let title: String
        let description: String?
        let privacy: PlaylistPrivacy?
    }

    /// A deletion waiting on its confirmation.
    private struct RemotePlaylistDeletion {
        let account: Account
        let playlistID: String
        let title: String
    }

    // View options (persisted)
    @AppStorage("playlists.layout") private var layout: VideoListLayout = .list
    @AppStorage("playlists.rowStyle") private var rowStyle: VideoRowStyle = .regular
    @AppStorage("playlists.gridColumns") private var gridColumns = 2

    // UI state
    @State private var showViewOptions = false
    @State private var viewWidth: CGFloat = 0

    // Grid layout configuration
    private var gridConfig: GridLayoutConfiguration {
        GridLayoutConfiguration(viewWidth: viewWidth, gridColumns: gridColumns)
    }

    private var dataManager: DataManager? { appEnvironment?.dataManager }

    /// List style from centralized settings.
    private var listStyle: VideoListStyle {
        appEnvironment?.settingsManager.listStyle ?? .inset
    }

    private var viewOptionsSheetContent: some View {
        ViewOptionsSheet(
            layout: $layout,
            rowStyle: $rowStyle,
            gridColumns: $gridColumns,
            maxGridColumns: gridConfig.maxColumns
        )
    }

    /// The delete confirmation, naming the playlist it is about.
    ///
    /// A playlist the server gave no title for falls back to the unnamed
    /// wording rather than asking about `""`.
    private var remoteDeletionTitle: String {
        guard let title = remoteDeletion?.title, !title.isEmpty else {
            return String(localized: "playlist.remote.delete.confirm")
        }
        return String(localized: "playlist.remote.delete.confirm.named \(title)")
    }

    /// View options button lives on the leading edge on macOS, trailing elsewhere.
    private var viewOptionsPlacement: ToolbarItemPlacement {
        #if os(macOS)
        .navigation
        #else
        .primaryAction
        #endif
    }

    // MARK: - Context

    /// The account whose playlists are on screen, or `nil` when these are the
    /// device's own.
    ///
    /// The *effective* context, so a selected account that cannot be used right
    /// now shows local playlists — with the banner saying why — instead of an
    /// empty list nobody can explain.
    private var contextAccount: Account? {
        guard let appEnvironment,
              case let .account(id) = appEnvironment.dataContextValidator.effectiveContext
        else { return nil }

        return appEnvironment.accountsManager.account(id: id)
    }

    /// Where a playlist created right now would go, or `nil` when there is
    /// nowhere to put one.
    ///
    /// The single answer both the create affordances and the row actions are
    /// gated on, so the button that offers a write and the write it performs
    /// can never have decided differently.
    private var creationTarget: PlaylistCreationTarget? {
        guard let appEnvironment else { return nil }
        let account = contextAccount

        return PlaylistCreationTarget.resolve(
            effectiveContext: appEnvironment.dataContextValidator.effectiveContext,
            account: account,
            allowsServerMutations: appEnvironment.dataContextValidator.allowsServerMutations,
            capabilities: account.flatMap { appEnvironment.accountsManager.capabilities(for: $0) }
        )
    }

    /// The account these playlists may be changed on.
    ///
    /// Both halves are asked even though reads only ever follow a valid context
    /// today: the write gate is what has to hold if that ever stops being true.
    private var writableAccount: Account? {
        guard case let .account(account) = creationTarget else { return nil }
        return account
    }

    /// Whether the create affordances have somewhere to create.
    private var canCreatePlaylist: Bool {
        creationTarget != nil
    }

    private var contextUnavailability: DataContextUnavailability? {
        guard appEnvironment?.accountsManager.currentContext.isLocal == false else { return nil }
        return appEnvironment?.dataContextValidator.unavailability
    }

    // MARK: - Rows

    /// The account's list as last fetched, or `nil` if it never was.
    ///
    /// Read live rather than copied into state: everything that changes a
    /// server-side playlist goes through the cache, so reading it is what makes
    /// a rename or a delete — here or in the detail view — show up.
    private var remotePlaylists: [Playlist]? {
        guard let appEnvironment, let account = contextAccount else { return nil }
        return appEnvironment.remotePlaylistsCache.playlists(for: account.id)
    }

    private var items: [PlaylistListItem] {
        guard contextAccount != nil else {
            return localPlaylists.map { .local($0) }
        }
        return (remotePlaylists ?? []).map { .remote($0) }
    }

    /// Playlists filtered by search.
    private var filteredItems: [PlaylistListItem] {
        PlaylistListItem.filtered(items, searchText: searchText)
    }

    /// Nothing fetched yet and no reason given — the spinner is for the first
    /// load only, a refetch leaves the previous list on screen.
    private var isLoadingRemoteList: Bool {
        contextAccount != nil && remotePlaylists == nil && remoteErrorMessage == nil
    }

    var body: some View {
        GeometryReader { geometry in
            Group {
                #if os(tvOS)
                tvOSContent
                #else
                content
                #endif
            }
            .onChange(of: geometry.size.width, initial: true) { _, newWidth in
                viewWidth = newWidth
            }
        }
        // Above the list rather than inside it: the rows are local data while
        // this is showing, and nothing else on screen says so.
        .safeAreaInset(edge: .top, spacing: 0) {
            if let contextUnavailability {
                DataContextUnavailableBanner(reason: contextUnavailability)
            }
        }
        #if !os(tvOS)
        .navigationTitle(String(localized: "home.playlists.title"))
        .toolbarTitleDisplayMode(.inlineLarge)
        .searchable(text: $searchText, prompt: Text(String(localized: "playlists.search.placeholder")))
        .refreshable {
            await load()
        }
        .toolbar {
            #if os(macOS)
            // Pin the trailing group (search field + toolbar buttons) to the right edge,
            // matching the global Search view.
            if #available(macOS 26, *) {
                ToolbarSpacer(.flexible, placement: .primaryAction)
            }
            #endif
            // No switcher on macOS: the sidebar row is the one persistent
            // switcher surface there.
            #if !os(macOS)
            if DataContextSwitcherVisibility.showsPickers(in: appEnvironment) {
                ToolbarItem(placement: viewOptionsPlacement) {
                    DataContextSwitcherMenu()
                }
            }
            #endif
            ToolbarItem(placement: viewOptionsPlacement) {
                Button {
                    showViewOptions = true
                } label: {
                    Label(String(localized: "viewOptions.title"), systemImage: "slider.horizontal.3")
                }
                .liquidGlassTransitionSource(id: "playlistsViewOptions", in: sheetTransition)
                #if os(macOS)
                .popover(isPresented: $showViewOptions, arrowEdge: .bottom) {
                    viewOptionsSheetContent
                }
                #endif
            }
            if canCreatePlaylist {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        beginCreate()
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
        }
        #endif
        #if !os(macOS)
        .sheet(isPresented: $showViewOptions) {
            viewOptionsSheetContent
                .liquidGlassSheetContent(sourceID: "playlistsViewOptions", in: sheetTransition)
        }
        #endif
        .sheet(item: $creation) { creation in
            if let account = creation.account {
                PlaylistFormSheet(
                    mode: .create,
                    showsPrivacy: supportsPrivacy(account)
                ) { title, description, privacy in
                    Task {
                        await createRemotePlaylist(
                            title: title,
                            description: description,
                            privacy: privacy,
                            on: account
                        )
                    }
                }
            } else {
                PlaylistFormSheet(mode: .create) { title, description in
                    _ = dataManager?.createPlaylist(title: title, description: description)
                    loadPlaylists()
                }
            }
        }
        .sheet(item: $playlistToEdit) { playlist in
            PlaylistFormSheet(mode: .edit(playlist)) { newTitle, newDescription in
                dataManager?.updatePlaylist(playlist, title: newTitle, description: newDescription)
                loadPlaylists()
            }
        }
        .sheet(item: $remoteEdit) { edit in
            PlaylistFormSheet(
                mode: .editRemote(
                    title: edit.title,
                    description: edit.description,
                    privacy: edit.privacy
                ),
                showsPrivacy: supportsPrivacy(edit.account)
            ) { newTitle, newDescription, newPrivacy in
                Task {
                    await saveRemoteEdit(
                        edit,
                        title: newTitle,
                        description: newDescription,
                        privacy: newPrivacy
                    )
                }
            }
        }
        // Taking a playlist off a server is a very different sentence from
        // deleting a local one, which stays unconfirmed as it always was.
        .confirmationDialog(
            remoteDeletionTitle,
            isPresented: Binding(
                get: { remoteDeletion != nil },
                set: { if !$0 { remoteDeletion = nil } }
            ),
            titleVisibility: .visible,
            presenting: remoteDeletion
        ) { deletion in
            Button(String(localized: "common.delete"), role: .destructive) {
                Task { await deleteRemotePlaylist(deletion) }
            }
        }
        .onAppear {
            startLoad()
        }
        .onReceive(NotificationCenter.default.publisher(for: .playlistsDidChange)) { _ in
            loadPlaylists()
        }
        // Selecting another account — or local — changes whose playlists these
        // are, and the previous ones may not be shown for a moment longer.
        .onReceive(NotificationCenter.default.publisher(for: .dataContextDidChange)) { _ in
            startLoad()
        }
        // The same, without the context moving: the credential behind the
        // account was replaced, so the list may now be someone else's.
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
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if isLoadingRemoteList {
            scrollableState {
                ProgressView()
                    .frame(maxWidth: .infinity)
            }
        } else if let remoteErrorMessage, items.isEmpty {
            scrollableState {
                remoteErrorView(remoteErrorMessage)
            }
        } else if filteredItems.isEmpty {
            scrollableState {
                emptyView
            }
        } else {
            switch layout {
            case .list:
                listContent
            case .grid:
                gridContent
            }
        }
    }

    /// A state with nothing to scroll, put in a scroll view anyway.
    ///
    /// Two things need one. Pull to refresh has nowhere to live without it —
    /// and a navigation bar carrying a search field keeps its full height over
    /// content that cannot scroll, which is what the banner was landing under.
    private func scrollableState(@ViewBuilder _ state: () -> some View) -> some View {
        ScrollView {
            state()
                .containerRelativeFrame(.vertical)
        }
    }

    #if os(tvOS)
    // MARK: - tvOS Content

    private var tvOSContent: some View {
        VStack(spacing: 0) {
            HStack(spacing: 24) {
                TextField(String(localized: "playlists.search.placeholder"), text: $searchText)
                    .textFieldStyle(.plain)

                if canCreatePlaylist {
                    Button {
                        beginCreate()
                    } label: {
                        Label(String(localized: "home.playlists.new"), systemImage: "plus")
                    }
                }

                // Pull to refresh has no equivalent here, and a server-side list
                // is the only one that can go stale.
                if contextAccount != nil {
                    Button {
                        startLoad()
                    } label: {
                        Label(String(localized: "common.refresh"), systemImage: "arrow.clockwise")
                    }
                }

                Button {
                    showViewOptions = true
                } label: {
                    Label(String(localized: "viewOptions.title"), systemImage: "slider.horizontal.3")
                }

                if DataContextSwitcherVisibility.showsPickers(in: appEnvironment) {
                    DataContextSwitcherButton()
                }
            }
            .focusSection()
            .padding(.horizontal, 48)
            .padding(.top, 20)
            .padding(.bottom, 20)

            content
                .focusSection()
        }
        .onChange(of: items.first?.id, initial: true) { _, newValue in
            // Work around tvOS focus bug: set initial focus to first playlist once cells materialize.
            // Only ever the first time cells appear — a refetch, or a switch the
            // user made in the header, must not pull focus out from under them.
            guard !didSetInitialFocus, let newValue else { return }
            didSetInitialFocus = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                focusedPlaylistID = newValue
            }
        }
    }
    #endif

    // MARK: - Empty View

    @ViewBuilder
    private var emptyView: some View {
        if !searchText.isEmpty {
            ContentUnavailableView.search(text: searchText)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            noPlaylistsView
        }
    }

    private var noPlaylistsView: some View {
        ContentUnavailableView {
            Label(String(localized: "home.playlists.title"), systemImage: "list.bullet.rectangle")
        } description: {
            Text(emptyDescription)
        } actions: {
            if canCreatePlaylist {
                Button {
                    beginCreate()
                } label: {
                    Label(String(localized: "home.playlists.new"), systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyDescription: String {
        contextAccount == nil
            ? String(localized: "home.empty.description")
            : String(localized: "playlists.selector.empty.account")
    }

    private func remoteErrorView(_ message: String) -> some View {
        ContentUnavailableView {
            Label(String(localized: "playlists.remote.load.error"), systemImage: "exclamationmark.triangle")
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

    // MARK: - List Content

    private var listContent: some View {
        VideoListContainer(listStyle: listStyle, rowStyle: rowStyle) {
            Spacer()
                .frame(height: 16)
        } content: {
            ForEach(Array(filteredItems.enumerated()), id: \.element.id) { index, item in
                listRow(item: item, index: index, count: filteredItems.count)
            }
        }
    }

    @ViewBuilder
    private func listRow(item: PlaylistListItem, index: Int, count: Int) -> some View {
        let row = VideoListRow(
            isLast: index == count - 1,
            rowStyle: rowStyle,
            listStyle: listStyle,
            contentWidth: rowStyle.thumbnailWidth
        ) {
            playlistRow(item: item)
        }
        #if !os(tvOS)
        .swipeActions(actionsArray: swipeActions(for: item))
        #endif

        #if os(tvOS)
        // There is no swipe here, so a menu is the only way to reach a
        // server-side playlist's actions. Local rows keep exactly the
        // affordances they had — and an account that may not change its
        // playlists gets no menu rather than an empty one.
        if case .remote = item, writableAccount != nil {
            row.contextMenu {
                rowActions(for: item)
            }
        } else {
            row
        }
        #else
        // Everywhere else the menu hangs off the row's button instead — see
        // `playlistRow(item:)`.
        row
        #endif
    }

    // MARK: - Grid Layout

    private var gridContent: some View {
        ScrollView {
            VideoGridContent(columns: gridConfig.effectiveColumns) {
                ForEach(filteredItems, id: \.id) { item in
                    playlistCard(item: item)
                }
            }
        }
        #if os(tvOS)
        .scrollClipDisabled()
        #endif
    }

    // MARK: - Helper Views

    @ViewBuilder
    private func playlistRow(item: PlaylistListItem) -> some View {
        #if os(tvOS)
        NavigationLink(value: NavigationDestination.playlist(source(for: item))) {
            rowContent(for: item)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .zoomTransitionSource(id: item.transitionID)
        .focused($focusedPlaylistID, equals: item.id)
        #else
        // A button rather than a tap gesture, and the menu hangs off the button
        // itself: that is what carries a row's actions to the accessibility
        // layer, exactly as a video row does. A bare shape with a gesture on it
        // is not a control, offers no `AXShowMenu` and cannot be reached from
        // the keyboard — and on macOS the menu is the only route to Edit and
        // Delete, swipe actions being iOS-only.
        let button = Button {
            appEnvironment?.navigationCoordinator.navigate(to: .playlist(source(for: item)))
        } label: {
            rowContent(for: item)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .zoomTransitionSource(id: item.transitionID)

        // Local rows keep exactly the affordances they had, and an account that
        // may not change its playlists gets no menu rather than an empty one.
        if case .remote = item, writableAccount != nil {
            button.contextMenu {
                rowActions(for: item)
            }
        } else {
            button
        }
        #endif
    }

    @ViewBuilder
    private func rowContent(for item: PlaylistListItem) -> some View {
        switch item {
        case let .local(playlist):
            PlaylistRowView(playlist: playlist, style: rowStyle)
        case let .remote(playlist):
            SearchPlaylistRowView(playlist: playlist, style: rowStyle)
        }
    }

    @ViewBuilder
    private func playlistCard(item: PlaylistListItem) -> some View {
        #if os(tvOS)
        let card = NavigationLink(value: NavigationDestination.playlist(source(for: item))) {
            cardContent(for: item)
                .frame(maxHeight: .infinity, alignment: .top)
        }
        .buttonStyle(.plain)
        .zoomTransitionSource(id: item.transitionID)
        .focused($focusedPlaylistID, equals: item.id)

        if case .remote = item, writableAccount != nil {
            card.contextMenu {
                rowActions(for: item)
            }
        } else {
            card
        }
        #else
        // A button for the same reason the list row is one: the card's menu is
        // only reachable by assistive tech and by the keyboard from a control.
        let card = Button {
            appEnvironment?.navigationCoordinator.navigate(to: .playlist(source(for: item)))
        } label: {
            cardContent(for: item)
                .frame(maxHeight: .infinity, alignment: .top)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .zoomTransitionSource(id: item.transitionID)

        if hasRowActions(item) {
            card.contextMenu {
                rowActions(for: item)
            }
        } else {
            card
        }
        #endif
    }

    /// Whether a row has anything to offer in a menu.
    ///
    /// Local rows always do. A server-side row needs an account that may change
    /// its playlists — an empty menu is worse than no menu at all.
    private func hasRowActions(_ item: PlaylistListItem) -> Bool {
        switch item {
        case .local: true
        case .remote: writableAccount != nil
        }
    }

    @ViewBuilder
    private func cardContent(for item: PlaylistListItem) -> some View {
        switch item {
        case let .local(playlist):
            LocalPlaylistCardView(playlist: playlist, isCompact: gridConfig.isCompactCards)
        case let .remote(playlist):
            PlaylistCardView(playlist: playlist, isCompact: gridConfig.isCompactCards)
        }
    }

    // MARK: - Navigation

    /// Where a row leads.
    ///
    /// A server-side playlist carries both the account's instance and the
    /// account's id, and they have to agree: the detail view only keeps
    /// ownership — and with it editing and deletion — when the id it is handed
    /// names an account on the instance it was opened for.
    private func source(for item: PlaylistListItem) -> PlaylistSource {
        switch item {
        case let .local(playlist):
            return .local(playlist.id, title: playlist.title)
        case let .remote(playlist):
            let account = contextAccount
            return .remote(
                playlist.id,
                instance: account.flatMap { appEnvironment?.accountsManager.instance(for: $0) },
                title: playlist.title,
                accountID: account?.id
            )
        }
    }

    // MARK: - Row Actions

    @ViewBuilder
    private func rowActions(for item: PlaylistListItem) -> some View {
        switch item {
        case let .local(playlist):
            Button {
                playlistToEdit = playlist
            } label: {
                Label(String(localized: "playlist.edit"), systemImage: "pencil")
            }
            Button(role: .destructive) {
                dataManager?.deletePlaylist(playlist)
                loadPlaylists()
            } label: {
                Label(String(localized: "playlist.delete"), systemImage: "trash")
            }

        case let .remote(playlist):
            if let account = writableAccount {
                Button {
                    beginRemoteEdit(playlist, on: account)
                } label: {
                    Label(String(localized: "playlist.edit"), systemImage: "pencil")
                }
                Button(role: .destructive) {
                    remoteDeletion = RemotePlaylistDeletion(
                        account: account,
                        playlistID: playlist.id.playlistID,
                        title: playlist.title
                    )
                } label: {
                    Label(String(localized: "playlist.delete"), systemImage: "trash")
                }
            }
        }
    }

    private func swipeActions(for item: PlaylistListItem) -> [SwipeAction] {
        switch item {
        case let .local(playlist):
            return [
                SwipeAction(
                    symbolImage: "pencil",
                    tint: .white,
                    background: .orange
                ) { reset in
                    playlistToEdit = playlist
                    reset()
                },
                SwipeAction(
                    symbolImage: "trash.fill",
                    tint: .white,
                    background: .red
                ) { reset in
                    dataManager?.deletePlaylist(playlist)
                    loadPlaylists()
                    reset()
                }
            ]

        case let .remote(playlist):
            guard let account = writableAccount else { return [] }
            return [
                // Closed before anything is awaited: an edit begins with a
                // refetch and a delete with a confirmation, and neither should
                // happen behind a row still standing open.
                SwipeAction(
                    symbolImage: "pencil",
                    tint: .white,
                    background: .orange
                ) { reset in
                    reset()
                    beginRemoteEdit(playlist, on: account)
                },
                SwipeAction(
                    symbolImage: "trash.fill",
                    tint: .white,
                    background: .red
                ) { reset in
                    reset()
                    remoteDeletion = RemotePlaylistDeletion(
                        account: account,
                        playlistID: playlist.id.playlistID,
                        title: playlist.title
                    )
                }
            ]
        }
    }

    private func supportsPrivacy(_ account: Account) -> Bool {
        appEnvironment?.accountsManager.capabilities(for: account)?.supportsPlaylistPrivacy == true
    }

    // MARK: - Creating

    /// Opens the form over the destination as it stands at this moment.
    ///
    /// Silent when there is nowhere to create: a toolbar item can outlive the
    /// condition that put it there, and a write with nowhere to go is not a
    /// write to somewhere else.
    private func beginCreate() {
        creation = creationTarget
    }

    private func createRemotePlaylist(
        title: String,
        description: String?,
        privacy: PlaylistPrivacy?,
        on account: Account
    ) async {
        guard let appEnvironment else { return }

        do {
            try await appEnvironment.remotePlaylistsCache.createPlaylist(
                title: title,
                description: description,
                privacy: privacy,
                for: account
            )
        } catch {
            appEnvironment.toastManager.showError(
                String(localized: "playlist.remote.create.error"),
                subtitle: error.localizedDescription
            )
        }
    }

    // MARK: - Editing

    /// Opens the edit form over the playlist as the server has it *now*.
    ///
    /// The form saves every field at once, so an edit started from a row fetched
    /// minutes ago would put that row's title and description back over anything
    /// changed since — by another client, or from the detail view. On failure
    /// there is no sheet: editing from data known to be stale is the thing this
    /// refetch exists to prevent.
    private func beginRemoteEdit(_ playlist: Playlist, on account: Account) {
        Task {
            guard let appEnvironment else { return }
            let playlistID = playlist.id.playlistID

            do {
                try await appEnvironment.remotePlaylistsCache.refreshSnapshot(id: playlistID, for: account)

                // Nothing came back to edit: the account was cleared while this
                // was in flight and its data went with it.
                guard let snapshot = appEnvironment.remotePlaylistsCache.snapshot(
                    id: playlistID,
                    for: account.id
                ) else { return }

                remoteEdit = RemotePlaylistEdit(
                    account: account,
                    playlistID: playlistID,
                    title: snapshot.playlist.title,
                    description: snapshot.playlist.description,
                    privacy: snapshot.isListed.map { $0 ? .public : .private }
                )
            } catch {
                appEnvironment.toastManager.showError(
                    String(localized: "playlist.remote.refresh.error"),
                    subtitle: error.localizedDescription
                )
            }
        }
    }

    private func saveRemoteEdit(
        _ edit: RemotePlaylistEdit,
        title: String,
        description: String?,
        privacy: PlaylistPrivacy?
    ) async {
        guard let appEnvironment else { return }

        do {
            try await appEnvironment.remotePlaylistsCache.updatePlaylist(
                id: edit.playlistID,
                title: title,
                description: description,
                privacy: privacy,
                for: edit.account
            )
        } catch {
            // A half-applied edit is a real outcome on Piped, where the name and
            // the description are two calls — the cache's refetch is what says
            // which half landed, and the rows are read straight out of it.
            appEnvironment.toastManager.showError(
                String(localized: "playlist.remote.edit.error"),
                subtitle: error.localizedDescription
            )
        }
    }

    private func deleteRemotePlaylist(_ deletion: RemotePlaylistDeletion) async {
        guard let appEnvironment else { return }

        do {
            try await appEnvironment.remotePlaylistsCache.deletePlaylist(
                id: deletion.playlistID,
                for: deletion.account
            )
        } catch {
            appEnvironment.toastManager.showError(
                String(localized: "playlist.remote.delete.error"),
                subtitle: error.localizedDescription
            )
        }
    }

    // MARK: - Loading

    private func startLoad() {
        loadTask?.cancel()
        loadTask = nil

        guard let (account, generation) = beginLoad() else { return }
        loadTask = Task { await fetchRemoteList(account, generation: generation) }
    }

    /// The same load, awaited — for pull to refresh, where the spinner has to
    /// stay up until the fetch is over.
    private func load() async {
        guard let (account, generation) = beginLoad() else { return }
        await fetchRemoteList(account, generation: generation)
    }

    private func reloadIfEffectiveContextMoved() {
        guard appEnvironment?.dataContextValidator.effectiveContext != loadedContext else { return }
        startLoad()
    }

    /// Records which context the rows belong to and loads the ones that are
    /// already here, returning the account whose list still has to be fetched.
    ///
    /// Local data is read synchronously and stays that way: an await before it
    /// would put the empty state on screen for a frame every time this view
    /// appears.
    private func beginLoad() -> (account: Account, generation: Int)? {
        guard let appEnvironment else { return nil }

        // Recorded on every load, not only on a context change: the first load
        // of a session has to establish what is on screen, or the first status
        // change would look like a move and reload for nothing.
        loadedContext = appEnvironment.dataContextValidator.effectiveContext
        loadGeneration += 1
        remoteErrorMessage = nil

        guard let account = contextAccount else {
            loadPlaylists()
            return nil
        }

        return (account, loadGeneration)
    }

    private func fetchRemoteList(_ account: Account, generation: Int) async {
        guard let appEnvironment else { return }

        do {
            try await appEnvironment.remotePlaylistsCache.refreshList(for: account)
        } catch is CancellationError {
            // Another load is taking over — it owns the state now.
        } catch let error as APIError where error == .cancelled {
            // The same, one layer down.
        } catch {
            guard generation == loadGeneration else { return }
            remoteErrorMessage = error.localizedDescription
        }
    }

    private func loadPlaylists() {
        localPlaylists = (dataManager?.playlists() ?? []).sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }
}
