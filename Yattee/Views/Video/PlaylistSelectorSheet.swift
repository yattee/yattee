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
                    // Create new playlist section
                    Section {
                        Button {
                            showingNewPlaylist = true
                        } label: {
                            Label(
                                String(localized: "playlist.new"),
                                systemImage: "plus.circle"
                            )
                        }
                    }

                    // Existing playlists
                    if !playlists.isEmpty {
                        Section {
                            ForEach(playlists, id: \.id) { playlist in
                                PlaylistSelectionRow(
                                    playlist: playlist,
                                    video: video,
                                    wasAdded: addedToPlaylist?.id == playlist.id
                                ) {
                                    addVideoToPlaylist(playlist)
                                }
                            }
                        } header: {
                            // Unlabelled while local playlists are the only
                            // destinations there are.
                            if !remoteDestinations.isEmpty {
                                Text(String(localized: "playlist.section.local"))
                            }
                        }
                    } else {
                        Section {
                            ContentUnavailableView {
                                Label(
                                    String(localized: "playlist.empty.title"),
                                    systemImage: "music.note.list"
                                )
                            } description: {
                                Text(String(localized: "playlist.empty.description"))
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                    }

                    ForEach(remoteDestinations) { account in
                        remoteSection(for: account)
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

    // MARK: - Remote Sections

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
                ForEach(remotePlaylists) { playlist in
                    RemotePlaylistSelectionRow(
                        playlist: playlist,
                        wasAdded: addedRemotePlaylist == RemoteSelection(
                            accountID: account.id,
                            playlistID: playlist.id.playlistID
                        )
                    ) {
                        Task { await addVideo(to: playlist, on: account) }
                    }
                }
            } else if loadingAccountIDs.contains(account.id) {
                ProgressView()
                    #if !os(tvOS)
                    .controlSize(.small)
                    #endif
                    .frame(maxWidth: .infinity)
            }
        } header: {
            Text(sectionTitle(for: account))
        }
    }

    /// The account's name, and the host it lives on when the name does not
    /// already carry it (a login shows up as `user@host`).
    private func sectionTitle(for account: Account) -> String {
        guard let appEnvironment else { return "" }

        let name = appEnvironment.dataContextValidator.displayName(for: account)
        guard let host = appEnvironment.accountsManager.instance(for: account)?.url.host,
              !name.localizedCaseInsensitiveContains(host)
        else { return name }

        return "\(name) · \(host)"
    }

    private func loadPlaylists() {
        playlists = dataManager?.playlists() ?? []
    }

    private func addVideoToPlaylist(_ playlist: LocalPlaylist) {
        guard let dataManager else { return }

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
        guard let appEnvironment else { return }

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
            // picks somewhere else.
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

                Image(systemName: wasAdded ? "checkmark.circle.fill" : "plus.circle")
                    .foregroundStyle(wasAdded ? .green : .secondary)
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
