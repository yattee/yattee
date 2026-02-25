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

    // Merge warning state
    @State private var showMergeWarning = false
    @State private var pendingMergePlaylist: Playlist?
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
            .navigationTitle(String(localized: "import.playlists.title"))
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
            .confirmationDialog(
                String(localized: "import.playlists.mergeWarning.title"),
                isPresented: $showMergeWarning,
                titleVisibility: .visible
            ) {
                Button(String(localized: "import.playlists.mergeWarning.merge")) {
                    if let playlist = pendingMergePlaylist, let localPlaylist = existingLocalPlaylist {
                        Task { await performImport(playlist, into: localPlaylist) }
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
              let credential = appEnvironment.credentialsManager(for: instance)?.credential(for: instance) else {
            error = ImportError.notLoggedIn
            isLoading = false
            return
        }

        isLoading = true
        error = nil

        do {
            let fetchedPlaylists: [Playlist]

            switch instance.type {
            case .invidious:
                let api = InvidiousAPI(httpClient: appEnvironment.httpClient)
                fetchedPlaylists = try await api.userPlaylists(instance: instance, sid: credential)

            case .piped:
                let api = PipedAPI(httpClient: appEnvironment.httpClient)
                fetchedPlaylists = try await api.userPlaylists(instance: instance, authToken: credential)

            default:
                throw ImportError.notSupported
            }

            playlists = fetchedPlaylists.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }

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

        // Check if local playlist with same title exists
        let localPlaylists = appEnvironment.dataManager.playlists()
        if let existing = localPlaylists.first(where: { $0.title == playlist.title }) {
            // Show merge warning
            pendingMergePlaylist = playlist
            existingLocalPlaylist = existing
            importingPlaylistID = playlist.id.playlistID
            showMergeWarning = true
            return
        }

        // Create new local playlist and import
        let localPlaylist = appEnvironment.dataManager.createPlaylist(title: playlist.title)
        await performImport(playlist, into: localPlaylist)
    }

    private func performImport(_ playlist: Playlist, into localPlaylist: LocalPlaylist) async {
        guard let appEnvironment,
              let credential = appEnvironment.credentialsManager(for: instance)?.credential(for: instance) else {
            return
        }

        importingPlaylistID = playlist.id.playlistID
        importProgress = nil
        pendingMergePlaylist = nil
        existingLocalPlaylist = nil

        do {
            // Fetch full playlist with videos
            let fullPlaylist: Playlist

            switch instance.type {
            case .invidious:
                let api = InvidiousAPI(httpClient: appEnvironment.httpClient)
                fullPlaylist = try await api.userPlaylist(
                    id: playlist.id.playlistID,
                    instance: instance,
                    sid: credential
                )

            case .piped:
                let api = PipedAPI(httpClient: appEnvironment.httpClient)
                fullPlaylist = try await api.userPlaylist(
                    id: playlist.id.playlistID,
                    instance: instance,
                    authToken: credential
                )

            default:
                throw ImportError.notSupported
            }

            let videos = fullPlaylist.videos
            let total = videos.count
            var skippedCount = 0

            for (index, video) in videos.enumerated() {
                // Update progress
                await MainActor.run {
                    importProgress = (current: index + 1, total: total)
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
                importedPlaylistIDs.insert(playlist.id.playlistID)
                importingPlaylistID = nil
                importProgress = nil

                if skippedCount > 0 {
                    appEnvironment.toastManager.showSuccess(
                        String(localized: "import.playlists.added.title"),
                        subtitle: String(localized: "import.playlists.skipped.subtitle \(skippedCount)")
                    )
                } else {
                    appEnvironment.toastManager.showSuccess(String(localized: "import.playlists.added.title"))
                }
            }
        } catch {
            await MainActor.run {
                importingPlaylistID = nil
                importProgress = nil
                appEnvironment.toastManager.showError(
                    String(localized: "import.playlists.failed.title"),
                    subtitle: error.localizedDescription
                )
            }
        }
    }

    private func addAllPlaylists() async {
        for playlist in unimportedPlaylists {
            await addPlaylist(playlist)

            // If merge warning is shown, wait for user interaction
            while showMergeWarning {
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
    }

    // MARK: - Errors

    enum ImportError: LocalizedError {
        case notLoggedIn
        case notSupported

        var errorDescription: String? {
            switch self {
            case .notLoggedIn:
                return String(localized: "import.playlists.notLoggedIn")
            case .notSupported:
                return String(localized: "import.playlists.notSupported")
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
