//
//  UnifiedPlaylistDetailView.swift
//  Yattee
//
//  Unified view for displaying both local and remote playlists.
//

import SwiftUI
import NukeUI

/// Cached playlist data for showing header immediately while loading.
private struct CachedPlaylistHeader {
    let title: String
    let thumbnailURL: URL?
    let videoCount: Int

    init(from recentPlaylist: RecentPlaylist) {
        title = recentPlaylist.title
        thumbnailURL = recentPlaylist.thumbnailURLString.flatMap { URL(string: $0) }
        videoCount = recentPlaylist.videoCount
    }
}

/// Source type for playlist data - either local (SwiftData) or remote (API).
enum PlaylistSource: Hashable {
    case local(UUID, title: String? = nil)
    case remote(PlaylistID, instance: Instance?, title: String? = nil)

    /// Initial title to show while loading (if provided).
    var initialTitle: String? {
        switch self {
        case .local(_, let title): return title
        case .remote(_, _, let title): return title
        }
    }

    /// Returns a unique identifier for zoom transitions.
    var transitionID: AnyHashable {
        switch self {
        case .local(let uuid, _):
            return uuid
        case .remote(let playlistID, _, _):
            return playlistID
        }
    }
}

struct UnifiedPlaylistDetailView: View {
    @Environment(\.appEnvironment) private var appEnvironment
    @Environment(\.dismiss) private var dismiss

    let source: PlaylistSource

    // MARK: - Shared State

    @State private var title: String

    init(source: PlaylistSource) {
        self.source = source
        self._title = State(initialValue: source.initialTitle ?? "")
    }
    @State private var descriptionText: String?
    @State private var thumbnailURL: URL?
    @State private var videos: [Video] = []
    @State private var videoCount: Int = 0

    // MARK: - Remote-only State

    @State private var isLoading = true
    @State private var cachedHeader: CachedPlaylistHeader?
    @State private var errorMessage: String?
    @State private var isImporting = false
    @State private var importProgress: (current: Int, total: Int)?
    @State private var remotePlaylist: Playlist?

    // MARK: - Local-only State

    @State private var localPlaylist: LocalPlaylist?
    @State private var showingEditSheet = false
    @State private var showingDeleteConfirmation = false
    @State private var isDescriptionExpanded = false

    #if !os(tvOS)
    @State private var downloadCoordinator = BatchDownloadCoordinator()
    // Cache download state to avoid triggering @Observable tracking on every render.
    // Prevents entire playlist view re-rendering when download progress updates.
    @State private var cachedAllVideosDownloaded = false
    @State private var hasLoadedDownloadState = false
    #endif

    private var dataManager: DataManager? { appEnvironment?.dataManager }
    private var isQueueEnabled: Bool { appEnvironment?.settingsManager.queueEnabled ?? true }

    private var isLocal: Bool {
        if case .local = source { return true }
        return false
    }

    /// Summary text for the playlist (e.g., "5 videos · 1h 23m").
    private var playlistSummaryText: String? {
        var parts: [String] = []

        if videoCount > 0 || !isLoading {
            parts.append(String(localized: "playlist.videoCount \(videoCount)"))
        }

        if let localPlaylist {
            parts.append(localPlaylist.formattedTotalDuration)
        }

        // Return placeholder while loading to prevent navigation subtitle jump
        if parts.isEmpty && isLoading {
            return String(localized: "common.loading")
        }

        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    // MARK: - Body

    var body: some View {
        Group {
            if !title.isEmpty || localPlaylist != nil {
                playlistContent
            } else if case .remote = source, isLoading, let cachedHeader {
                // Show header with cached data + spinner for video list
                loadingContent(cachedHeader)
            } else if case .remote = source, isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = errorMessage {
                errorView(error)
            } else {
                ContentUnavailableView(
                    String(localized: "playlist.notFound"),
                    systemImage: "list.bullet.rectangle",
                    description: Text(String(localized: "playlist.notFound.description"))
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle(title.isEmpty ? String(localized: "playlist.title") : title)
        #if !os(tvOS)
        .toolbarTitleDisplayMode(.inlineLarge)
        #endif
        .navigationSubtitleIfAvailable(playlistSummaryText)
        #if os(tvOS)
        .toolbar {
            if !videos.isEmpty || localPlaylist != nil {
                ToolbarItem(placement: .primaryAction) {
                    toolbarMenu
                }
            }
        }
        #endif
        .sheet(isPresented: $showingEditSheet) {
            if let localPlaylist {
                PlaylistFormSheet(mode: .edit(localPlaylist)) { newTitle, newDescription in
                    dataManager?.updatePlaylist(localPlaylist, title: newTitle, description: newDescription)
                    loadLocalPlaylist()
                }
            }
        }
        .confirmationDialog(
            String(localized: "playlist.delete.confirm"),
            isPresented: $showingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button(String(localized: "common.delete"), role: .destructive) {
                if let localPlaylist {
                    dataManager?.deletePlaylist(localPlaylist)
                    dismiss()
                }
            }
        }
        .task {
            await loadPlaylist()
        }
        #if !os(tvOS)
        .batchDownload(coordinator: downloadCoordinator)
        .onAppear {
            downloadCoordinator.setEnvironment(appEnvironment)
            loadDownloadStateIfNeeded()
        }
        .onChange(of: videos) { _, _ in
            // Update cache when videos change (e.g., after loading)
            updateAllVideosDownloadedCache()
        }
        #endif
    }

    // MARK: - Content

    @ViewBuilder
    private var playlistContent: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                playlistHeader

                Divider()
                    .padding(.horizontal)

                if videos.isEmpty {
                    if isLoading {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding(.top, 40)
                    } else {
                        emptyPlaylistView
                    }
                } else {
                    videoList
                }
            }
        }
        .refreshable {
            if case .remote = source {
                await loadPlaylist()
            }
        }
    }

    /// Shows cached header with a spinner below while loading full playlist data.
    private func loadingContent(_ cached: CachedPlaylistHeader) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                playlistHeader(
                    thumbnailURL: cached.thumbnailURL,
                    videoCount: cached.videoCount
                )

                Divider()
                    .padding(.horizontal)

                // Centered spinner for content area
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.top, 40)
            }
        }
    }

    private var playlistHeader: some View {
        playlistHeader(
            thumbnailURL: thumbnailURL,
            videoCount: videoCount,
            localPlaylist: localPlaylist,
            descriptionText: descriptionText
        )
    }

    private func playlistHeader(
        thumbnailURL: URL?,
        videoCount: Int,
        localPlaylist: LocalPlaylist? = nil,
        descriptionText: String? = nil
    ) -> some View {
        // Build summary text for this header instance
        let summaryText: String? = {
            var parts: [String] = []
            if videoCount > 0 || !isLoading {
                parts.append(String(localized: "playlist.videoCount \(videoCount)"))
            }
            if let localPlaylist {
                parts.append(localPlaylist.formattedTotalDuration)
            }
            return parts.isEmpty ? nil : parts.joined(separator: " · ")
        }()

        return VStack(alignment: .leading, spacing: 12) {
            // Summary info (only shown on pre-iOS 26, or non-iOS platforms)
            #if os(iOS)
            if #unavailable(iOS 26) {
                if let summaryText {
                    Text(summaryText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            #else
            // Show on non-iOS platforms (macOS, tvOS)
            if let summaryText {
                Text(summaryText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            #endif

            // Description (full width, expandable)
            if let descriptionText, !descriptionText.isEmpty {
                ExpandableText(text: descriptionText, lineLimit: 2, isExpanded: $isDescriptionExpanded)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            #if !os(tvOS)
            // Action buttons row (iOS/macOS only)
            if !videos.isEmpty || localPlaylist != nil {
                playlistActionButtons
            }
            #endif
        }
        .padding()
    }

    // MARK: - Action Buttons Row

    #if !os(tvOS)
    @ViewBuilder
    private var playlistActionButtons: some View {
        HStack(spacing: 12) {
            // Play button (only when queue is enabled)
            if isQueueEnabled {
                Button {
                    playAll()
                } label: {
                    Label(String(localized: "playlist.play"), systemImage: "play.fill")
                        .fontWeight(.semibold)
                }
                .buttonStyle(.borderedProminent)
            }

            // Download button with three states
            if downloadCoordinator.isDownloading {
                Button {
                    // No action while downloading
                } label: {
                    HStack(spacing: 6) {
                        ProgressView()
                            .controlSize(.small)
                        if let progress = downloadCoordinator.progress {
                            Text("\(progress.current)/\(progress.total)")
                                .monospacedDigit()
                        }
                    }
                }
                .fontWeight(.semibold)
                .buttonStyle(.bordered)
                .disabled(true)
            } else if cachedAllVideosDownloaded {
                Button {
                    // No action - already downloaded
                } label: {
                    Label(String(localized: "playlist.downloaded"), systemImage: "checkmark.circle.fill")
                }
                .fontWeight(.semibold)
                .buttonStyle(.bordered)
                .disabled(true)
            } else {
                Button {
                    downloadCoordinator.startDownload(videos: videos)
                } label: {
                    Label(String(localized: "playlist.downloadAll"), systemImage: "arrow.down.circle")
                }
                .fontWeight(.semibold)
                .buttonStyle(.bordered)
            }

            Spacer()

            // Menu button (circular with glass background)
            Menu {
                // Remote-only: Save to Library, Share
                if case .remote = source, let remotePlaylist, !remotePlaylist.isLocal {
                    Button {
                        Task { await importToLocal() }
                    } label: {
                        if isImporting, let progress = importProgress {
                            Label(String(localized: "playlist.savingToLibrary \(progress.current) \(progress.total)"), systemImage: "plus.rectangle.on.folder")
                        } else {
                            Label(String(localized: "playlist.saveToLibrary"), systemImage: "plus.rectangle.on.folder")
                        }
                    }
                    .disabled(isImporting)

                    ShareLink(item: playlistShareURL()) {
                        Label(String(localized: "common.share"), systemImage: "square.and.arrow.up")
                    }
                }

                // Local-only: Edit, Delete
                if isLocal, localPlaylist != nil {
                    Button {
                        showingEditSheet = true
                    } label: {
                        Label(String(localized: "playlist.edit"), systemImage: "pencil")
                    }

                    Button(role: .destructive) {
                        showingDeleteConfirmation = true
                    } label: {
                        Label(String(localized: "playlist.delete"), systemImage: "trash")
                    }
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.body.weight(.medium))
                    .frame(width: 44, height: 44)
                    .background(.regularMaterial, in: Circle())
            }
        }
        .padding(.top, 8)
    }
    #endif

    // MARK: - Toolbar Menu

    @ViewBuilder
    private var toolbarMenu: some View {
        Menu {
            // Play (only when queue is enabled)
            if isQueueEnabled {
                Button {
                    playAll()
                } label: {
                    Label(String(localized: "playlist.play"), systemImage: "play.fill")
                }
            }

            #if !os(tvOS)
            // Download All
            if downloadCoordinator.isDownloading {
                Label {
                    if let progress = downloadCoordinator.progress {
                        Text("\(progress.current)/\(progress.total)")
                    } else {
                        Text(String(localized: "common.downloading"))
                    }
                } icon: {
                    Image(systemName: "arrow.down.circle")
                }
            } else {
                Button {
                    downloadCoordinator.startDownload(videos: videos)
                } label: {
                    Label(String(localized: "playlist.downloadAll"), systemImage: "arrow.down.circle")
                }
                .disabled(cachedAllVideosDownloaded)
            }
            #endif

            // Remote-only: Save to Library, Share
            if case .remote = source, let remotePlaylist, !remotePlaylist.isLocal {
                Button {
                    Task { await importToLocal() }
                } label: {
                    if isImporting, let progress = importProgress {
                        Label(String(localized: "playlist.savingToLibrary \(progress.current) \(progress.total)"), systemImage: "plus.rectangle.on.folder")
                    } else {
                        Label(String(localized: "playlist.saveToLibrary"), systemImage: "plus.rectangle.on.folder")
                    }
                }
                .disabled(isImporting)

                #if !os(tvOS)
                ShareLink(item: playlistShareURL()) {
                    Label(String(localized: "common.share"), systemImage: "square.and.arrow.up")
                }
                #endif
            }

            // Local-only: Edit, Delete
            if isLocal, localPlaylist != nil {
                Divider()

                Button {
                    showingEditSheet = true
                } label: {
                    Label(String(localized: "playlist.edit"), systemImage: "pencil")
                }

                Button(role: .destructive) {
                    showingDeleteConfirmation = true
                } label: {
                    Label(String(localized: "playlist.delete"), systemImage: "trash")
                }
            }
        } label: {
            Image(systemName: "ellipsis")
        }
    }

    #if !os(tvOS)
    /// Loads download state once on appear to avoid continuous re-renders from @Observable.
    private func loadDownloadStateIfNeeded() {
        guard !hasLoadedDownloadState else { return }
        hasLoadedDownloadState = true
        updateAllVideosDownloadedCache()
    }

    /// Updates the cached allVideosDownloaded state.
    /// Called on appear and when videos array changes.
    private func updateAllVideosDownloadedCache() {
        guard let downloadManager = appEnvironment?.downloadManager else {
            cachedAllVideosDownloaded = false
            return
        }
        cachedAllVideosDownloaded = videos.allSatisfy { video in
            downloadManager.downloadedVideoIDs.contains(video.id) ||
            downloadManager.downloadingVideoIDs.contains(video.id)
        }
    }
    #endif

    private var emptyPlaylistView: some View {
        ContentUnavailableView {
            Label(String(localized: "playlist.empty"), systemImage: "music.note.list")
        } description: {
            Text(String(localized: "playlist.empty.description"))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, 40)
    }

    private var videoList: some View {
        LazyVStack(spacing: 0) {
            ForEach(Array(videos.enumerated()), id: \.element.id) { index, video in
                VideoListRow(
                    isLast: index == videos.count - 1,
                    rowStyle: .regular,
                    listStyle: .plain,
                    indexWidth: 32  // Index column width in VideoRowView
                ) {
                    Button {
                        playFromIndex(index)
                    } label: {
                        PlaylistVideoRowView(
                            index: index + 1,
                            video: video,
                            onRemove: isLocal ? { removeVideo(at: index) } : nil
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Error View

    private func errorView(_ error: String) -> some View {
        ContentUnavailableView {
            Label(String(localized: "common.error"), systemImage: "exclamationmark.triangle")
        } description: {
            Text(error)
        } actions: {
            Button(String(localized: "common.retry")) {
                Task { await loadPlaylist() }
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Data Loading

    private func loadPlaylist() async {
        switch source {
        case .local:
            loadLocalPlaylist()
        case .remote(let playlistID, let instance, _):
            await loadRemotePlaylist(playlistID: playlistID, instance: instance)
        }
    }

    private func loadLocalPlaylist() {
        guard case .local(let uuid, _) = source else { return }

        localPlaylist = dataManager?.playlists().first { $0.id == uuid }

        if let playlist = localPlaylist {
            title = playlist.title
            descriptionText = playlist.playlistDescription
            thumbnailURL = playlist.thumbnailURL
            videos = playlist.sortedItems.map { $0.toVideo() }
            videoCount = playlist.videoCount
        }

        isLoading = false
    }

    private func loadRemotePlaylist(playlistID: PlaylistID, instance: Instance?) async {
        guard let appEnvironment else {
            errorMessage = "App not initialized"
            isLoading = false
            return
        }

        // Use passed instance, or find appropriate one based on source
        let targetInstance: Instance?
        if let instance {
            targetInstance = instance
        } else if let playlistSource = playlistID.source {
            targetInstance = instanceForSource(playlistSource, instancesManager: appEnvironment.instancesManager)
        } else {
            targetInstance = appEnvironment.instancesManager.activeInstance
        }

        guard let resolvedInstance = targetInstance else {
            errorMessage = "No instance available"
            isLoading = false
            return
        }

        isLoading = true
        errorMessage = nil

        // Load cached header data for immediate display
        if let recentPlaylist = appEnvironment.dataManager.recentPlaylistEntry(forPlaylistID: playlistID.playlistID) {
            cachedHeader = CachedPlaylistHeader(from: recentPlaylist)
        }

        do {
            let fetchedPlaylist: Playlist

            // Check if this is an Invidious user playlist (IVPL prefix) that requires authentication
            let isInvidiousUserPlaylist = playlistID.playlistID.hasPrefix("IVPL")
            let isInvidiousInstance = resolvedInstance.type == .invidious
            let sid = appEnvironment.invidiousCredentialsManager.sid(for: resolvedInstance)

            if isInvidiousUserPlaylist && isInvidiousInstance, let sid {
                // Use authenticated endpoint for Invidious user playlists (including private ones)
                let api = InvidiousAPI(httpClient: appEnvironment.httpClient)
                fetchedPlaylist = try await api.userPlaylist(
                    id: playlistID.playlistID,
                    instance: resolvedInstance,
                    sid: sid
                )
            } else {
                // Use public endpoint for regular playlists
                fetchedPlaylist = try await appEnvironment.contentService.playlist(
                    id: playlistID.playlistID,
                    instance: resolvedInstance
                )
            }

            remotePlaylist = fetchedPlaylist
            title = fetchedPlaylist.title
            descriptionText = fetchedPlaylist.description
            thumbnailURL = fetchedPlaylist.thumbnailURL
            videos = fetchedPlaylist.videos
            videoCount = fetchedPlaylist.videoCount

            // Save to recent playlists (only remote playlists, unless incognito mode is enabled or recent playlists disabled)
            if appEnvironment.settingsManager.incognitoModeEnabled != true,
               appEnvironment.settingsManager.saveRecentPlaylists {
                appEnvironment.dataManager.addRecentPlaylist(fetchedPlaylist)
            }
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    /// Returns the appropriate instance for the playlist's content source.
    private func instanceForSource(_ source: ContentSource, instancesManager: InstancesManager) -> Instance? {
        switch source {
        case .global:
            // For global content (YouTube), prefer Invidious instances over Yattee Server
            // since Invidious playlists (IVPL*) are Invidious-specific
            if let invidiousInstance = instancesManager.enabledInstances.first(where: { $0.type == .invidious }) {
                return invidiousInstance
            }
            // Fall back to any YouTube-compatible instance
            return instancesManager.enabledInstances.first(where: { $0.isYouTubeInstance })
        case .federated(let provider, let instanceURL):
            // For federated content, find matching instance by URL
            if let existingInstance = instancesManager.instances.first(where: { $0.url == instanceURL }) {
                return existingInstance
            }
            // If no configured instance matches, create a temporary one for PeerTube
            if provider == ContentSource.peertubeProvider {
                return Instance(type: .peertube, url: instanceURL)
            }
            return nil
        case .extracted:
            // For extracted content, use Yattee Server
            return instancesManager.yatteeServerInstances.first
        }
    }

    // MARK: - Playback Actions

    private func playFromIndex(_ index: Int) {
        guard let appEnvironment else { return }

        appEnvironment.queueManager.playFromList(
            videos: videos,
            index: index,
            queueSource: queueSource,
            sourceLabel: title
        )
    }

    private func playAll() {
        guard !videos.isEmpty, let appEnvironment else { return }

        appEnvironment.queueManager.playFromList(
            videos: videos,
            index: 0,
            queueSource: queueSource,
            sourceLabel: title
        )
    }

    private var queueSource: QueueSource {
        switch source {
        case .local:
            return .manual
        case .remote(let playlistID, _, _):
            return .playlist(playlistID: playlistID.playlistID, continuation: nil)
        }
    }

    // MARK: - Local Playlist Actions

    private func removeVideo(at index: Int) {
        guard let localPlaylist else { return }
        dataManager?.removeVideoFromPlaylist(at: index, playlist: localPlaylist)
        loadLocalPlaylist()
    }

    // MARK: - Remote Playlist Actions

    private func playlistShareURL() -> URL {
        guard let remotePlaylist else {
            return URL(string: "yattee://playlist")!
        }

        switch remotePlaylist.id.source {
        case .global:
            return URL(string: "https://youtube.com/playlist?list=\(remotePlaylist.id.playlistID)")!
        case .federated(_, let instance):
            return instance.appendingPathComponent("video-playlists/\(remotePlaylist.id.playlistID)")
        case .extracted(_, let originalURL):
            return originalURL
        case nil:
            return URL(string: "yattee://playlist/\(remotePlaylist.id.playlistID)")!
        }
    }

    /// Generates a unique playlist name by appending (2), (3), etc. if needed.
    private func generateUniqueName(_ baseName: String, existingTitles: Set<String>) -> String {
        if !existingTitles.contains(baseName) {
            return baseName
        }

        var counter = 2
        while true {
            let candidateName = "\(baseName) (\(counter))"
            if !existingTitles.contains(candidateName) {
                return candidateName
            }
            counter += 1
        }
    }

    /// Imports the remote playlist to local storage.
    private func importToLocal() async {
        guard let appEnvironment, let remotePlaylist else { return }

        isImporting = true
        importProgress = nil

        // Generate unique name
        let existingTitles = Set(appEnvironment.dataManager.playlists().map(\.title))
        let uniqueName = generateUniqueName(remotePlaylist.title, existingTitles: existingTitles)

        // Create local playlist
        let newLocalPlaylist = appEnvironment.dataManager.createPlaylist(
            title: uniqueName,
            description: remotePlaylist.description
        )

        // Add videos
        let total = videos.count

        for (index, video) in videos.enumerated() {
            importProgress = (current: index + 1, total: total)
            appEnvironment.dataManager.addToPlaylist(video, playlist: newLocalPlaylist)

            // Small delay to allow UI to update for larger playlists
            if total > 10 {
                try? await Task.sleep(for: .milliseconds(30))
            }
        }

        isImporting = false
        importProgress = nil

        appEnvironment.toastManager.showSuccess(String(localized: "playlist.imported.title"))
    }
}

// MARK: - Preview

#Preview("Local Playlist") {
    NavigationStack {
        UnifiedPlaylistDetailView(source: .local(UUID()))
    }
    .appEnvironment(.preview)
}

#Preview("Remote Playlist") {
    NavigationStack {
        UnifiedPlaylistDetailView(source: .remote(.global("PLtest"), instance: nil))
    }
    .appEnvironment(.preview)
}
