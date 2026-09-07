//
//  ImportPlaylistsView.swift
//  Yattee
//
//  View for importing playlists from an Invidious or Piped instance to local storage.
//

import SwiftUI

struct ImportPlaylistsView: View {
    let instance: Instance

    @Environment(\.appEnvironment) private var appEnvironment

    @State private var playlists: [Playlist] = []
    @State private var importedPlaylistIDs: Set<String> = []
    @State private var isLoading = true
    @State private var error: Error?
    @State private var showAddAllConfirmation = false

    // Import progress state
    @State private var importingPlaylistID: String?
    @State private var importProgress: (current: Int, total: Int)?
    /// Set when an import stopped because the login behind it changed, so a
    /// batch stops with it: everything after would either be read under a
    /// different account or leave an empty playlist behind for one that is
    /// gone.
    @State private var loginChangedDuringImport = false
    /// The merge started from the confirmation dialog, which runs detached
    /// from the batch that queued it. Held so the batch can wait for it.
    @State private var mergeImportTask: Task<Void, Never>?
    /// The credential the listed playlists were read with. Everything on
    /// screen belongs to it, so every import is checked against this rather
    /// than against whatever is current — a replacement is a different
    /// person's account, and its playlist IDs mean something else entirely.
    @State private var loadedCredential: String?
    /// Which listing the imports in flight belong to. Reloading the list
    /// invalidates them: they were chosen from rows that are being replaced,
    /// and the credential they are checked against is about to move.
    @State private var listGeneration = 0

    // Merge warning state
    @State private var showMergeWarning = false
    @State private var pendingMergePlaylist: Playlist?
    /// The listing and login the pending merge was chosen from. The dialog
    /// waits on the user, so both can be replaced before they answer it.
    @State private var pendingMergeGeneration = 0
    @State private var pendingMergeCredential = ""
    @State private var existingLocalPlaylist: LocalPlaylist?

    // MARK: - Accessibility Identifiers

    private enum AccessibilityID {
        static let view = "import.playlists.view"
        static let loadingIndicator = "import.playlists.loading"
        static let errorMessage = "import.playlists.error"
        static let emptyState = "import.playlists.empty"
        static let list = "import.playlists.list"
        static func row(_ playlistID: String) -> String {
            "import.playlists.row.\(playlistID)"
        }
        static func addButton(_ playlistID: String) -> String {
            "import.playlists.add.\(playlistID)"
        }
        static func importedIndicator(_ playlistID: String) -> String {
            "import.playlists.imported.\(playlistID)"
        }
        static let addAllButton = "import.playlists.addAll"
    }

    // MARK: - Body

    var body: some View {
        content
            #if !os(tvOS)
            .navigationTitle(String(localized: "import.playlists.title"))
            #endif
            .accessibilityIdentifier(AccessibilityID.view)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                if !unimportedPlaylists.isEmpty && importingPlaylistID == nil {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            showAddAllConfirmation = true
                        } label: {
                            Label(String(localized: "import.playlists.addAll"), systemImage: "plus.circle")
                        }
                        .accessibilityIdentifier(AccessibilityID.addAllButton)
                    }
                }
            }
            .confirmationDialog(
                String(localized: "import.playlists.addAllConfirmation \(unimportedPlaylists.count)"),
                isPresented: $showAddAllConfirmation,
                titleVisibility: .visible
            ) {
                Button(String(localized: "import.playlists.addAll")) {
                    Task { await addAllPlaylists() }
                }
            }
            .presentationCompactAdaptation(.sheet)
            .confirmationDialog(
                String(localized: "import.playlists.mergeWarning.title"),
                isPresented: $showMergeWarning,
                titleVisibility: .visible
            ) {
                Button(String(localized: "import.playlists.mergeWarning.merge")) {
                    if let playlist = pendingMergePlaylist, let localPlaylist = existingLocalPlaylist {
                        let generation = pendingMergeGeneration
                        let credential = pendingMergeCredential
                        mergeImportTask = Task {
                            await performImport(
                                playlist,
                                into: localPlaylist,
                                generation: generation,
                                credential: credential
                            )
                        }
                    }
                }
                Button(String(localized: "common.cancel"), role: .cancel) {
                    pendingMergePlaylist = nil
                    existingLocalPlaylist = nil
                    importingPlaylistID = nil
                }
            } message: {
                if let playlist = pendingMergePlaylist {
                    Text(String(localized: "import.playlists.mergeWarning.message \(playlist.title)"))
                }
            }
            .presentationCompactAdaptation(.sheet)
            .task {
                await loadPlaylists()
            }
    }

    // MARK: - Content Views

    @ViewBuilder
    private var content: some View {
        if isLoading {
            loadingView
        } else if let error {
            errorView(error)
        } else if playlists.isEmpty {
            emptyView
        } else {
            listView
        }
    }

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
            Text(String(localized: "import.playlists.loading"))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier(AccessibilityID.loadingIndicator)
    }

    private func errorView(_ error: Error) -> some View {
        ContentUnavailableView {
            Label(String(localized: "import.playlists.error"), systemImage: "exclamationmark.triangle")
        } description: {
            Text(error.localizedDescription)
        } actions: {
            Button(String(localized: "common.retry")) {
                Task { await loadPlaylists() }
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier(AccessibilityID.errorMessage)
    }

    private var emptyView: some View {
        ContentUnavailableView(
            String(localized: "import.playlists.emptyTitle"),
            systemImage: "list.bullet.rectangle",
            description: Text(String(localized: "import.playlists.emptyDescription"))
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier(AccessibilityID.emptyState)
    }

    private var listView: some View {
        List {
            ForEach(playlists) { playlist in
                playlistRow(playlist)
                    .accessibilityIdentifier(AccessibilityID.row(playlist.id.playlistID))
            }
        }
        .opaqueSettingsFormBackground()
        .accessibilityIdentifier(AccessibilityID.list)
    }

    // MARK: - Row View

    @ViewBuilder
    private func playlistRow(_ playlist: Playlist) -> some View {
        HStack(spacing: 12) {
            // Thumbnail
            if let thumbnailURL = playlist.thumbnailURL {
                AsyncImage(url: thumbnailURL) { image in
                    image
                        .resizable()
                        .aspectRatio(16/9, contentMode: .fill)
                } placeholder: {
                    Rectangle()
                        .fill(.quaternary)
                        .overlay {
                            Image(systemName: "list.bullet.rectangle")
                                .foregroundStyle(.secondary)
                        }
                }
                .frame(width: 64, height: 36)
                .clipShape(RoundedRectangle(cornerRadius: 4))
            } else {
                Rectangle()
                    .fill(.quaternary)
                    .frame(width: 64, height: 36)
                    .overlay {
                        Image(systemName: "list.bullet.rectangle")
                            .foregroundStyle(.secondary)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }

            // Title and video count
            VStack(alignment: .leading, spacing: 2) {
                Text(playlist.title)
                    .lineLimit(1)

                Text(String(localized: "import.playlists.videoCount \(playlist.videoCount)"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Import progress, imported indicator, or add button
            if importingPlaylistID == playlist.id.playlistID {
                importProgressView
            } else if importedPlaylistIDs.contains(playlist.id.playlistID) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .imageScale(.large)
                    .accessibilityIdentifier(AccessibilityID.importedIndicator(playlist.id.playlistID))
            } else {
                Button {
                    Task { await addPlaylist(playlist) }
                } label: {
                    Image(systemName: "plus.circle")
                        .imageScale(.large)
                }
                .buttonStyle(.borderless)
                .disabled(importingPlaylistID != nil)
                .accessibilityIdentifier(AccessibilityID.addButton(playlist.id.playlistID))
            }
        }
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var importProgressView: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)

            if let progress = importProgress {
                Text(String(localized: "import.playlists.importingProgress \(progress.current) \(progress.total)"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text(String(localized: "import.playlists.importing"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Computed Properties

    private var unimportedPlaylists: [Playlist] {
        playlists.filter { !importedPlaylistIDs.contains($0.id.playlistID) }
    }

    // MARK: - Actions

    private func loadPlaylists() async {
        guard let appEnvironment,
              let credential = appEnvironment.credential(forInstance: instance) else {
            error = ImportError.notLoggedIn
            isLoading = false
            return
        }

        isLoading = true
        error = nil
        // Anything still importing was chosen from the rows being replaced.
        listGeneration += 1
        loginChangedDuringImport = false
        // Its progress belongs to a row that is going away. Left set, the
        // incoming listing renders it against whichever row carries that ID
        // now — another account's playlist, shown as importing.
        importingPlaylistID = nil
        importProgress = nil

        do {
            guard instance.type.accountCapabilities.supportsPlaylistReads else {
                throw ImportError.notSupported
            }

            let fetchedPlaylists = try await appEnvironment.contentService.userPlaylists(
                instance: instance,
                credential: credential
            )

            playlists = fetchedPlaylists.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
            // Recorded only now: the baseline is whichever login actually
            // produced the rows on screen. A failed load leaves the previous
            // one standing, so an import still running keeps being checked
            // against the login that listed it.
            loadedCredential = credential

            // Check which playlists are already imported (by matching title)
            let localPlaylists = appEnvironment.dataManager.playlists()
            let localTitles = Set(localPlaylists.map(\.title))

            // Mark as imported if a local playlist with the same title exists
            importedPlaylistIDs = Set(
                playlists.filter { localTitles.contains($0.title) }.map(\.id.playlistID)
            )

            isLoading = false
        } catch {
            self.error = error
            isLoading = false
        }
    }

    private func addPlaylist(_ playlist: Playlist) async {
        guard let appEnvironment else { return }

        // Both taken here rather than wherever the import eventually starts: a
        // merge waits on the user, and by then the list may have been replaced
        // and its credential re-recorded.
        let generation = listGeneration

        // Checked before anything is created: a playlist made for a login that
        // has already gone would be left behind empty, because the import
        // aborts on its first write.
        guard let credential = appEnvironment.credential(forInstance: instance),
              credential == loadedCredential else {
            loginChangedDuringImport = true
            return
        }

        // Check if local playlist with same title exists
        let localPlaylists = appEnvironment.dataManager.playlists()
        if let existing = localPlaylists.first(where: { $0.title == playlist.title }) {
            // Show merge warning
            pendingMergePlaylist = playlist
            pendingMergeGeneration = generation
            pendingMergeCredential = credential
            existingLocalPlaylist = existing
            importingPlaylistID = playlist.id.playlistID
            showMergeWarning = true
            return
        }

        // Create new local playlist and import
        let localPlaylist = appEnvironment.dataManager.createPlaylist(title: playlist.title)
        let imported = await performImport(
            playlist,
            into: localPlaylist,
            generation: generation,
            credential: credential
        )

        // It is created before it is read, so anything that stops the read —
        // a login that moved, but equally a server that did not answer —
        // leaves it behind with nothing in it. An import that genuinely had
        // nothing to add keeps its playlist; a failed one does not.
        if !imported, localPlaylist.items?.isEmpty ?? true {
            appEnvironment.dataManager.deletePlaylist(localPlaylist)
        }
    }

    /// - Parameters:
    ///   - generation: the listing `playlist` was chosen from, taken at
    ///     selection time. It decides only what may be marked imported — a
    ///     reload replaces the rows, not the login.
    ///   - credential: the login that listed `playlist`, taken at selection
    ///     time. Reading it under any other would fetch whatever that ID
    ///     happens to name to somebody else.
    /// - Returns: whether the playlist was read and written in full.
    @discardableResult
    private func performImport(
        _ playlist: Playlist,
        into localPlaylist: LocalPlaylist,
        generation: Int,
        credential: String
    ) async -> Bool {
        guard let appEnvironment else { return false }

        // The login can go, or be replaced, between choosing this playlist and
        // reading it — the merge dialog in particular waits on the user.
        // Returning quietly would leave the row importing forever and let a
        // batch carry on.
        guard appEnvironment.credential(forInstance: instance) == credential else {
            loginChangedDuringImport = true
            importingPlaylistID = nil
            importProgress = nil
            pendingMergePlaylist = nil
            existingLocalPlaylist = nil
            appEnvironment.toastManager.showError(
                String(localized: "import.playlists.failed.title"),
                subtitle: ImportError.loginChanged.localizedDescription
            )
            return false
        }

        importingPlaylistID = playlist.id.playlistID
        importProgress = nil
        pendingMergePlaylist = nil
        existingLocalPlaylist = nil

        do {
            guard instance.type.accountCapabilities.supportsPlaylistReads else {
                throw ImportError.notSupported
            }

            // Fetch full playlist with videos. The snapshot's per-row identities
            // are of no use to an import — nothing here is written back to the
            // server — so only the playlist itself is taken.
            let fullPlaylist = try await appEnvironment.contentService.userPlaylistSnapshot(
                id: playlist.id.playlistID,
                instance: instance,
                credential: credential
            ).playlist

            let videos = fullPlaylist.videos
            let total = videos.count
            var skippedCount = 0

            for (index, video) in videos.enumerated() {
                // Update progress
                await MainActor.run {
                    importProgress = (current: index + 1, total: total)
                }

                // These videos are private to the login they were read with,
                // and the destination is not: local playlists are shared by
                // whoever uses the device and sync to iCloud. The sheet can be
                // dismissed and somebody else signed in on the same server
                // while this runs, so the credential is checked before every
                // write rather than only at the start. What has already been
                // written stays — it was imported under the login that asked
                // for it.
                guard appEnvironment.credential(forInstance: instance) == credential else {
                    throw ImportError.loginChanged
                }

                // Skip if already in playlist
                if localPlaylist.contains(videoID: video.id.videoID) {
                    skippedCount += 1
                    continue
                }

                // Add video to local playlist
                appEnvironment.dataManager.addToPlaylist(video, playlist: localPlaylist)

                // Small delay to allow UI to update and not overwhelm the system
                try? await Task.sleep(for: .milliseconds(50))
            }

            await MainActor.run {
                importingPlaylistID = nil
                importProgress = nil

                // The list can be replaced after the last video is written —
                // an empty remote playlist never reaches a check at all.
                // Marking it imported would attach to whatever row carries
                // that ID now, which on another account is a different
                // playlist.
                guard generation == listGeneration else { return }

                importedPlaylistIDs.insert(playlist.id.playlistID)

                if skippedCount > 0 {
                    appEnvironment.toastManager.showSuccess(
                        String(localized: "import.playlists.added.title"),
                        subtitle: String(localized: "import.playlists.skipped.subtitle \(skippedCount)")
                    )
                } else {
                    appEnvironment.toastManager.showSuccess(String(localized: "import.playlists.added.title"))
                }
            }

            return true
        } catch {
            await MainActor.run {
                if error as? ImportError == .loginChanged {
                    loginChangedDuringImport = true
                }
                importingPlaylistID = nil
                importProgress = nil
                appEnvironment.toastManager.showError(
                    String(localized: "import.playlists.failed.title"),
                    subtitle: error.localizedDescription
                )
            }

            return false
        }
    }

    private func addAllPlaylists() async {
        loginChangedDuringImport = false
        let generation = listGeneration

        for playlist in unimportedPlaylists {
            // The rows this batch is working through have been replaced, and
            // the remaining ones no longer describe what is on screen.
            guard generation == listGeneration else { break }

            await addPlaylist(playlist)

            // If merge warning is shown, wait for user interaction
            while showMergeWarning {
                try? await Task.sleep(for: .milliseconds(100))
            }

            // The merge the dialog starts is detached from it, so dismissing
            // the dialog is not the merge finishing. Waiting keeps the batch
            // sequential — and lets a login change the merge runs into stop
            // the rest, rather than the next import beginning under whoever
            // replaced it.
            await mergeImportTask?.value
            mergeImportTask = nil

            // The rest of the batch belongs to a login that is no longer
            // there. Reported once, by whichever import stopped first.
            if loginChangedDuringImport { break }
        }
    }

    // MARK: - Errors

    enum ImportError: LocalizedError, Equatable {
        case notLoggedIn
        case notSupported
        case loginChanged

        var errorDescription: String? {
            switch self {
            case .notLoggedIn:
                return String(localized: "import.playlists.notLoggedIn")
            case .notSupported:
                return String(localized: "import.playlists.notSupported")
            case .loginChanged:
                return String(localized: "import.playlists.loginChanged")
            }
        }
    }
}

// MARK: - Preview

#Preview("Invidious") {
    NavigationStack {
        ImportPlaylistsView(
            instance: Instance(type: .invidious, url: URL(string: "https://invidious.example.com")!)
        )
        .appEnvironment(.preview)
    }
}

#Preview("Piped") {
    NavigationStack {
        ImportPlaylistsView(
            instance: Instance(type: .piped, url: URL(string: "https://piped.example.com")!)
        )
        .appEnvironment(.preview)
    }
}
