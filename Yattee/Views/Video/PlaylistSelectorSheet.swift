//
//  PlaylistSelectorSheet.swift
//  Yattee
//
//  Sheet for selecting a playlist to add a video to.
//

import SwiftUI
import NukeUI

struct PlaylistSelectorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appEnvironment) private var appEnvironment

    let video: Video

    @State private var playlists: [LocalPlaylist] = []
    @State private var showingNewPlaylist = false
    @State private var pendingPlaylistTitle: String?
    @State private var pendingPlaylistDescription: String?
    @State private var addedToPlaylist: LocalPlaylist?

    // MARK: - Remote Destinations

    /// One account's playlist. Two accounts can hold ids that look alike, so the
    /// account is part of naming one.
    private struct RemoteSelection: Equatable {
        let accountID: UUID
        let playlistID: String
    }

    /// The server-side playlist the video was just added to, so its row can show
    /// the same check the local ones do.
    @State private var addedRemotePlaylist: RemoteSelection?

    /// Accounts whose list is being fetched with nothing cached to show yet.
    @State private var loadingAccountIDs: Set<UUID> = []

    /// The account a new server-side playlist is being created on.
    @State private var newRemotePlaylistAccount: Account?

    /// Which destination's playlists the sheet is showing.
    ///
    /// Seeded from the app's selected data context, but a private copy from
    /// then on: picking a different account here changes what this sheet
    /// offers and nothing else — adding a video somewhere is not a decision
    /// to browse there.
    @State private var selectedDestination: DataContext = .local

    /// Seed once per presentation; `onAppear` must not stomp a pick the user
    /// already made if the view reappears.
    @State private var destinationSeeded = false

    private var dataManager: DataManager? { appEnvironment?.dataManager }

    /// Every account that can be added to, on every instance — not just the one
    /// currently selected as the data context. Adding a video to a playlist is
    /// not a browsing decision, and the user may well mean the other login.
    ///
    /// The same three things the write layer insists on, asked here so an
    /// account that could only ever fail is not offered as somewhere to put a
    /// video: the backend must do playlist writes, the instance must be one
    /// this app still talks to, and there must be a credential to talk with.
    /// Account *status* deliberately is not among them — a stale "rejected"
    /// would hide a login that works, and a failed add says so with a toast.
    private var remoteDestinations: [Account] {
        guard let appEnvironment else { return [] }
        return appEnvironment.accountsManager.accounts.filter { account in
            appEnvironment.accountsManager.capabilities(for: account)?.supportsPlaylistWrites == true
                && appEnvironment.accountsManager.instance(for: account)?.isEnabled == true
                && appEnvironment.accountCredentialsManager(for: account)?.isLoggedIn(for: account) == true
        }
    }

    var body: some View {
        NavigationStack {
            List {
                // Warning for local folder videos
                if video.isFromLocalFolder {
                    Section {
                        Label {
                            Text(String(localized: "playlist.localFileWarning"))
                        } icon: {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                        }
                    }
                }

                // Only show playlist options if not from local folder
                if !video.isFromLocalFolder {
                    // One destination shown at a time, picked at the top. No
                    // picker while local playlists are the only destination
                    // there is.
                    if !remoteDestinations.isEmpty {
                        Section {
                            destinationPicker
                        }
                    }

                    if let account = selectedAccount {
                        remoteSection(for: account)
                    } else {
                        localSection
                    }
                }
            }
            #if os(tvOS)
            .scrollClipDisabled()
            .padding(.horizontal, 40)
            .padding(.vertical, 24)
            #else
            .navigationTitle(String(localized: "playlist.addTo"))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                sheetCloseToolbarItem { dismiss() }
            }
            #endif
            .sheet(isPresented: $showingNewPlaylist) {
                PlaylistFormSheet(mode: .create) { title, description in
                    pendingPlaylistTitle = title
                    pendingPlaylistDescription = description
                }
            }
            .onChange(of: pendingPlaylistTitle) { _, newValue in
                if newValue != nil {
                    createAndAddToPlaylist()
                }
            }
            .onAppear {
                loadPlaylists()
                seedDestination()
            }
            .task {
                await refreshRemotePlaylists()
            }
        }
        // Attached outside the stack, so it is never the second sheet on the
        // same view as the local "New Playlist" one.
        .sheet(item: $newRemotePlaylistAccount) { account in
            PlaylistFormSheet(
                mode: .create,
                showsPrivacy: appEnvironment?.accountsManager
                    .capabilities(for: account)?.supportsPlaylistPrivacy == true
            ) { title, description, privacy in
                Task {
                    await createRemotePlaylist(
                        on: account,
                        title: title,
                        description: description,
                        privacy: privacy
                    )
                }
            }
        }
        #if os(iOS)
        .presentationDetents([.medium, .large])
        #endif
        #if os(macOS)
        .frame(minWidth: 450, minHeight: 500)
        #endif
    }

    // MARK: - Destination Picker

    /// The account whose playlists are on show, when the pick is not local.
    ///
    /// Resolved against the *eligible* accounts, so a login that stops
    /// qualifying mid-presentation quietly falls back to the local list
    /// instead of a section that could only fail.
    private var selectedAccount: Account? {
        guard case let .account(id) = selectedDestination else { return nil }
        return remoteDestinations.first { $0.id == id }
    }

    private var destinationPicker: some View {
        Picker(String(localized: "accounts.switcher.title"), selection: $selectedDestination) {
            Text(DataContextSwitcherLabels.title(for: .local, in: appEnvironment))
                .tag(DataContext.local)

            ForEach(remoteDestinations) { account in
                Text(DataContextSwitcherLabels.title(for: .account(account.id), in: appEnvironment))
                    .tag(DataContext.account(account.id))
            }
        }
        .pickerStyle(.menu)
    }

    /// The pick the sheet opens on: the account the app is browsing as, when
    /// that account is somewhere a video can be put — otherwise local, which
    /// always is.
    private func seedDestination() {
        guard !destinationSeeded else { return }
        destinationSeeded = true

        guard let current = appEnvironment?.accountsManager.currentContext,
              case let .account(id) = current,
              remoteDestinations.contains(where: { $0.id == id })
        else { return }

        selectedDestination = current
    }

    // MARK: - Sections

    private var localSection: some View {
        Section {
            Button {
                showingNewPlaylist = true
            } label: {
                Label(
                    String(localized: "playlist.new"),
                    systemImage: "plus.circle"
                )
            }

            if playlists.isEmpty {
                emptyDestinationsRow(
                    String(localized: "playlists.selector.empty.local")
                )
            } else {
                ForEach(playlists, id: \.id) { playlist in
                    PlaylistSelectionRow(
                        playlist: playlist,
                        video: video,
                        wasAdded: addedToPlaylist?.id == playlist.id
                    ) {
                        addVideoToPlaylist(playlist)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func remoteSection(for account: Account) -> some View {
        Section {
            Button {
                newRemotePlaylistAccount = account
            } label: {
                Label(
                    String(localized: "playlist.new"),
                    systemImage: "plus.circle"
                )
            }

            if let remotePlaylists = appEnvironment?.remotePlaylistsCache.playlists(for: account.id) {
                if remotePlaylists.isEmpty {
                    // The fetch landed and the account simply has none, which is
                    // worth saying — the "New Playlist" row above it is the only
                    // other thing in the section.
                    emptyDestinationsRow(
                        String(localized: "playlists.selector.empty.account")
                    )
                } else {
                    ForEach(remotePlaylists) { playlist in
                        let selection = RemoteSelection(
                            accountID: account.id,
                            playlistID: playlist.id.playlistID
                        )
                        RemotePlaylistSelectionRow(
                            playlist: playlist,
                            wasAdded: addedRemotePlaylist == selection,
                            isAdding: remoteAddInFlight == selection
                        ) {
                            Task { await addVideo(to: playlist, on: account) }
                        }
                    }
                }
            } else if loadingAccountIDs.contains(account.id) {
                ProgressView()
                    #if !os(tvOS)
                    .controlSize(.small)
                    #endif
                    .frame(maxWidth: .infinity)
            }
        }
    }

    /// Says that a section has no playlists to offer — not that some playlist is
    /// empty, which is a different sentence entirely.
    private func emptyDestinationsRow(_ text: String) -> some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(.secondary)
    }

    private func loadPlaylists() {
        playlists = dataManager?.playlists() ?? []
    }

    /// Whether a tap on a playlist may still start an add.
    ///
    /// One add per presentation: after a tap lands, the sheet is only showing
    /// its checkmark until the auto-dismiss — the same row is still on screen
    /// and still tappable, so without this a quick double-tap put the video in
    /// twice. A remote add holds the gate for the whole round-trip; only a
    /// failure reopens it, since failing is the one way the sheet stays up.
    private var canStartAdd: Bool {
        remoteAddInFlight == nil && addedToPlaylist == nil && addedRemotePlaylist == nil
    }

    /// The row whose add is on the wire, so that row — and only that row — can
    /// show a spinner where its plus was.
    @State private var remoteAddInFlight: RemoteSelection?

    private func addVideoToPlaylist(_ playlist: LocalPlaylist) {
        guard let dataManager, canStartAdd else { return }

        dataManager.addToPlaylist(video, playlist: playlist)
        addedToPlaylist = playlist

        // Auto-dismiss after a short delay to show the checkmark
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            dismiss()
        }
    }

    // MARK: - Remote Actions

    /// Refetches every eligible account's list, all at once.
    ///
    /// Failures are left silent: a section that cannot be filled simply offers
    /// its "New Playlist" row, and the error the user needs to see is the one
    /// from the add they actually tried.
    private func refreshRemotePlaylists() async {
        guard let appEnvironment else { return }

        let accounts = remoteDestinations
        loadingAccountIDs.formUnion(
            accounts.filter { appEnvironment.remotePlaylistsCache.playlists(for: $0.id) == nil }
                .map(\.id)
        )

        await withTaskGroup(of: Void.self) { group in
            for account in accounts {
                group.addTask { @MainActor in
                    try? await appEnvironment.remotePlaylistsCache.refreshList(for: account)
                    loadingAccountIDs.remove(account.id)
                }
            }
        }
    }

    private func addVideo(to playlist: Playlist, on account: Account) async {
        guard let appEnvironment, canStartAdd else { return }
        remoteAddInFlight = RemoteSelection(
            accountID: account.id,
            playlistID: playlist.id.playlistID
        )

        do {
            try await appEnvironment.remotePlaylistsCache.addVideo(
                videoID: video.id.videoID,
                toPlaylist: playlist.id.playlistID,
                for: account
            )

            addedRemotePlaylist = RemoteSelection(
                accountID: account.id,
                playlistID: playlist.id.playlistID
            )

            // Same beat as the local path: the check is shown, then the sheet
            // goes away.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                dismiss()
            }
        } catch {
            // No dismissal on failure — the sheet is where the user retries, or
            // picks somewhere else. Retrying means the gate reopens.
            remoteAddInFlight = nil
            appEnvironment.toastManager.showError(
                String(localized: "playlist.remote.add.error"),
                subtitle: error.localizedDescription
            )
        }
    }

    private func createRemotePlaylist(
        on account: Account,
        title: String,
        description: String?,
        privacy: PlaylistPrivacy?
    ) async {
        guard let appEnvironment else { return }

        do {
            let playlist = try await appEnvironment.remotePlaylistsCache.createPlaylist(
                title: title,
                description: description,
                privacy: privacy,
                for: account
            )
            await addVideo(to: playlist, on: account)
        } catch {
            appEnvironment.toastManager.showError(
                String(localized: "playlist.remote.create.error"),
                subtitle: error.localizedDescription
            )
        }
    }

    private func createAndAddToPlaylist() {
        guard let dataManager, let title = pendingPlaylistTitle else { return }

        let newPlaylist = dataManager.createPlaylist(title: title, description: pendingPlaylistDescription)
        dataManager.addToPlaylist(video, playlist: newPlaylist)
        pendingPlaylistTitle = nil
        pendingPlaylistDescription = nil
        addedToPlaylist = newPlaylist

        // Refresh list and auto-dismiss
        loadPlaylists()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            dismiss()
        }
    }
}

// MARK: - Playlist Selection Row

private struct PlaylistSelectionRow: View {
    let playlist: LocalPlaylist
    let video: Video
    let wasAdded: Bool
    let onAdd: () -> Void

    var body: some View {
        Button(action: onAdd) {
            HStack(spacing: 12) {
                // Thumbnail
                LazyImage(url: playlist.thumbnailURL) { state in
                    if let image = state.image {
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } else {
                        Rectangle()
                            .fill(.quaternary)
                            .overlay {
                                Image(systemName: "music.note.list")
                                    .foregroundStyle(.secondary)
                            }
                    }
                }
                .frame(width: 60, height: 34)
                .clipShape(RoundedRectangle(cornerRadius: 6))

                // Info
                VStack(alignment: .leading, spacing: 2) {
                    Text(playlist.title)
                        .font(.body)
                        .foregroundStyle(.primary)

                    Text(String(localized: "playlist.videoCount \(playlist.videoCount)"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                // Status
                if wasAdded {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else if playlist.contains(videoID: video.id.videoID) {
                    Text(String(localized: "playlist.alreadyAdded"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Image(systemName: "plus.circle")
                        .foregroundStyle(.secondary)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(playlist.contains(videoID: video.id.videoID) && !wasAdded)
    }
}

// MARK: - Remote Playlist Selection Row

/// A destination that lives on a server.
///
/// It never says "already added": the list fetch does not carry the playlist's
/// videos (Piped's rows are not in it at all), so membership is unknowable from
/// here. Guessing would be worse than the duplicate — which is the server's
/// business anyway.
private struct RemotePlaylistSelectionRow: View {
    let playlist: Playlist
    let wasAdded: Bool
    let isAdding: Bool
    let onAdd: () -> Void

    var body: some View {
        Button(action: onAdd) {
            HStack(spacing: 12) {
                // Single URL with no fallback chain, so the always-available
                // variant is the one that gets asked for.
                LazyImage(url: Thumbnail.reliableURL(for: playlist.thumbnailURL)) { state in
                    if let image = state.image {
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } else {
                        Rectangle()
                            .fill(.quaternary)
                            .overlay {
                                Image(systemName: "music.note.list")
                                    .foregroundStyle(.secondary)
                            }
                    }
                }
                .frame(width: 60, height: 34)
                .clipShape(RoundedRectangle(cornerRadius: 6))

                VStack(alignment: .leading, spacing: 2) {
                    Text(playlist.title)
                        .font(.body)
                        .foregroundStyle(.primary)

                    Text(String(localized: "playlist.videoCount \(playlist.videoCount)"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                // The checkmark wins: success replaces the spinner, not the
                // other way round.
                if wasAdded {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else if isAdding {
                    ProgressView()
                        #if !os(tvOS)
                        .controlSize(.small)
                        #endif
                } else {
                    Image(systemName: "plus.circle")
                        .foregroundStyle(.secondary)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Preview

#Preview {
    PlaylistSelectorSheet(video: .preview)
        .appEnvironment(.preview)
}
