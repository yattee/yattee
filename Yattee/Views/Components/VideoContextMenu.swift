//
//  VideoContextMenu.swift
//  Yattee
//
//  Shared context menu for video items.
//

import SwiftUI

// MARK: - Types

/// A custom action to display in the video context menu.
struct VideoContextAction {
    let label: String
    let systemImage: String
    let role: ButtonRole?
    let action: () -> Void

    init(_ label: String, systemImage: String, role: ButtonRole? = nil, action: @escaping () -> Void) {
        self.label = label
        self.systemImage = systemImage
        self.role = role
        self.action = action
    }
}

/// Context indicating which view the menu is being shown from.
/// Used to customize built-in menu items based on the current view.
enum VideoContextMenuContext {
    case `default`        // Standard behavior (show all items)
    case history          // Viewing history list
    case bookmarks        // Viewing bookmarks (hide bookmark toggle)
    case playlist         // Viewing a playlist
    case continueWatching // Continue watching section
    case downloads        // Viewing downloads (hide download option, bookmark toggle)
    case mediaBrowser     // Browsing media source files (hide bookmark toggle, playlist, download)
    case player           // In player view (hide play action - video already playing)
}

// MARK: - View Modifier

/// View modifier that attaches VideoContextMenu and its required sheets.
struct VideoContextMenuModifier: ViewModifier {
    let video: Video
    var customActions: [VideoContextAction] = []
    var context: VideoContextMenuContext = .default
    var startTime: Double? = nil
    var watchProgress: Double? = nil

    @Environment(\.appEnvironment) private var appEnvironment
    @State private var showingPlaylistSheet = false
    @State private var showingDownloadSheet = false
    @State private var showingDeleteDownloadConfirmation = false
    @State private var downloadToDelete: Download?
    @State private var menuRefreshID = UUID()

    func body(content: Content) -> some View {
        content
            #if os(tvOS)
            .contextMenu {
                VideoContextMenuContent(
                    video: video,
                    customActions: customActions,
                    context: context,
                    startTime: startTime,
                    showingPlaylistSheet: $showingPlaylistSheet,
                    showingDownloadSheet: $showingDownloadSheet,
                    showingDeleteDownloadConfirmation: $showingDeleteDownloadConfirmation,
                    downloadToDelete: $downloadToDelete,
                    appEnvironment: appEnvironment
                )
                .id(menuRefreshID)
            }
            #else
            .contextMenu(menuItems: {
                VideoContextMenuContent(
                    video: video,
                    customActions: customActions,
                    context: context,
                    startTime: startTime,
                    showingPlaylistSheet: $showingPlaylistSheet,
                    showingDownloadSheet: $showingDownloadSheet,
                    showingDeleteDownloadConfirmation: $showingDeleteDownloadConfirmation,
                    downloadToDelete: $downloadToDelete,
                    appEnvironment: appEnvironment
                )
                .id(menuRefreshID)
            }, preview: {
                VideoRowView(
                    video: video,
                    style: .regular,
                    watchProgress: watchProgress,
                    disableInternalTapHandling: true
                )
                .frame(width: 320)
                .padding()
                .environment(\.appEnvironment, appEnvironment)
            })
            #endif
            .sheet(isPresented: $showingPlaylistSheet) {
                PlaylistSelectorSheet(video: video)
            }
            #if !os(tvOS)
            .sheet(isPresented: $showingDownloadSheet) {
                DownloadQualitySheet(video: video)
            }
            .alert(String(localized: "videoInfo.download.remove.title"), isPresented: $showingDeleteDownloadConfirmation) {
                Button(String(localized: "common.cancel"), role: .cancel) {}
                Button(String(localized: "videoInfo.download.remove.confirm"), role: .destructive) {
                    if let download = downloadToDelete {
                        Task {
                            await appEnvironment?.downloadManager.delete(download)
                        }
                    }
                }
            } message: {
                Text(String(localized: "videoInfo.download.remove.message"))
            }
            #endif
            .onReceive(NotificationCenter.default.publisher(for: .watchHistoryDidChange)) { _ in
                menuRefreshID = UUID()
            }
    }
}

// MARK: - Menu Content

/// The actual menu content (uses bindings from parent for sheet presentation).
/// All observable values are snapshotted at init time to prevent redraws during playback.
struct VideoContextMenuContent: View {
    let video: Video
    var customActions: [VideoContextAction] = []
    var context: VideoContextMenuContext = .default
    var startTime: Double? = nil
    @Binding var showingPlaylistSheet: Bool
    @Binding var showingDownloadSheet: Bool
    @Binding var showingDeleteDownloadConfirmation: Bool
    @Binding var downloadToDelete: Download?

    @Environment(\.appEnvironment) private var appEnvironment

    // MARK: - Snapshotted Values (captured at init to prevent observation)

    /// Snapshotted remote control enabled state.
    private let remoteControlEnabled: Bool
    /// Snapshotted discovered devices list.
    private let snapshotDevices: [DiscoveredDevice]
    /// Snapshotted queue enabled setting.
    private let queueEnabled: Bool
    /// Snapshotted bookmark state.
    private let isBookmarked: Bool
    /// Snapshotted downloading state.
    private let isDownloading: Bool
    /// Snapshotted active download.
    private let activeDownload: Download?
    /// Snapshotted downloaded state.
    private let isDownloaded: Bool
    /// Snapshotted download object for deletion.
    private let snapshotDownload: Download?
    /// Snapshotted state indicating if queue has items (video playing or queued).
    private let hasQueueItems: Bool

    // MARK: - Init

    init(
        video: Video,
        customActions: [VideoContextAction] = [],
        context: VideoContextMenuContext = .default,
        startTime: Double? = nil,
        showingPlaylistSheet: Binding<Bool>,
        showingDownloadSheet: Binding<Bool>,
        showingDeleteDownloadConfirmation: Binding<Bool> = .constant(false),
        downloadToDelete: Binding<Download?> = .constant(nil),
        appEnvironment: AppEnvironment? = nil
    ) {
        self.video = video
        self.customActions = customActions
        self.context = context
        self.startTime = startTime
        self._showingPlaylistSheet = showingPlaylistSheet
        self._showingDownloadSheet = showingDownloadSheet
        self._showingDeleteDownloadConfirmation = showingDeleteDownloadConfirmation
        self._downloadToDelete = downloadToDelete

        // Snapshot observable values to prevent view updates during playback
        self.remoteControlEnabled = appEnvironment?.remoteControlCoordinator.isEnabled ?? false
        self.snapshotDevices = appEnvironment?.remoteControlCoordinator.discoveredDevices ?? []
        self.queueEnabled = appEnvironment?.settingsManager.queueEnabled ?? true
        self.isBookmarked = appEnvironment?.dataManager.isBookmarked(videoID: video.id.videoID) ?? false
        self.isDownloading = appEnvironment?.downloadManager.isDownloading(video.id) ?? false
        self.activeDownload = appEnvironment?.downloadManager.download(for: video.id)
        self.isDownloaded = appEnvironment?.downloadManager.isDownloaded(video.id) ?? false
        // Snapshot download for potential deletion
        self.snapshotDownload = appEnvironment?.downloadManager.download(for: video.id)
        // Queue actions only make sense when there's already a video playing or queued
        let playerState = appEnvironment?.playerService.state
        self.hasQueueItems = playerState?.currentVideo != nil || playerState?.hasNext == true
    }

    // MARK: - Computed Properties (context-based, not observable)

    /// Whether to show the bookmark toggle based on context
    private var showBookmarkToggle: Bool {
        !video.isFromLocalFolder && context != .bookmarks && context != .downloads && context != .mediaBrowser
    }

    /// Whether to show add to playlist based on context
    private var showAddToPlaylist: Bool {
        !video.isFromLocalFolder && context != .mediaBrowser
    }

    /// Whether to show the download option based on context
    private var showDownloadOption: Bool {
        context != .downloads
    }

    /// Whether to show Go to channel based on context
    private var showGoToChannel: Bool {
        context != .mediaBrowser
    }

    /// Whether to show the play action based on context
    private var showPlayAction: Bool {
        context != .player
    }

    /// Whether to show queue actions based on context, settings, and queue state
    private var showQueueActions: Bool {
        context != .player && queueEnabled && hasQueueItems
    }

    /// Computed at render time to always show current watch state
    private var isWatched: Bool {
        appEnvironment?.dataManager.watchEntry(for: video.id.videoID)?.isFinished ?? false
    }

    var body: some View {
        // Custom actions at the top
        ForEach(customActions.indices, id: \.self) { index in
            let action = customActions[index]
            Button(role: action.role) {
                action.action()
            } label: {
                Label(action.label, systemImage: action.systemImage)
            }
        }

        // Divider after custom actions (if any)
        if !customActions.isEmpty {
            Divider()
        }
        
        ControlGroup {
            // Play (hidden in player context since video is already playing)
            if showPlayAction {
                Button {
                    if let startTime {
                        appEnvironment?.playerService.openVideo(video, startTime: startTime)
                    } else {
                        appEnvironment?.playerService.openVideo(video)
                    }
                } label: {
                    Label(String(localized: "video.context.play"), systemImage: "play.fill")
                }
            }
            
            #if !os(tvOS)
            // Download / Cancel download / Downloaded
            if showDownloadOption {
                if isDownloading, let download = activeDownload {
                    Button(role: .destructive) {
                        Task {
                            await appEnvironment?.downloadManager.cancel(download)
                        }
                    } label: {
                        Label(String(localized: "video.context.cancelDownload"), systemImage: "xmark.circle")
                    }
                } else if isDownloaded, let download = snapshotDownload {
                    Button {
                        downloadToDelete = download
                        showingDeleteDownloadConfirmation = true
                    } label: {
                        Label(String(localized: "video.context.downloaded"), systemImage: "checkmark.circle.fill")
                    }
                } else {
                    Button {
                        startDownload(for: video)
                    } label: {
                        Label(String(localized: "video.context.download"), systemImage: "arrow.down.circle")
                    }
                }
            }
            #endif

            // Share
            #if !os(tvOS)
            ShareLink(item: video.shareURL) {
                Label(String(localized: "video.context.share"), systemImage: "square.and.arrow.up")
            }
            #endif
        }

        // Play from Beginning (only shown when there's saved progress)
        if showPlayAction, let startTime, startTime > 0 {
            Button {
                appEnvironment?.playerService.openVideo(video, startTime: 0)
            } label: {
                Label(String(localized: "video.context.playFromBeginning"), systemImage: "arrow.counterclockwise")
            }
        }

        // Mark as Watched / Unwatched
        if !video.isFromLocalFolder {
            Button {
                if isWatched {
                    appEnvironment?.dataManager.markAsUnwatched(videoID: video.id.videoID)
                } else {
                    appEnvironment?.dataManager.markAsWatched(video: video)
                }
            } label: {
                if isWatched {
                    Label(String(localized: "video.context.markUnwatched"), systemImage: "eye.slash")
                } else {
                    Label(String(localized: "video.context.markWatched"), systemImage: "eye")
                }
            }
        }

        // Queue actions (hidden in player context and when queue feature is disabled)
        if showQueueActions {
            Button {
                appEnvironment?.queueManager.playNext(video)
            } label: {
                Label(String(localized: "video.context.playNext"), systemImage: "text.line.first.and.arrowtriangle.forward")
            }

            Button {
                appEnvironment?.queueManager.addToQueue(video)
            } label: {
                Label(String(localized: "video.context.addToQueue"), systemImage: "text.append")
            }
        }

        // Play on remote devices (for non-player contexts - play video directly on remote device)
        if context != .player, remoteControlEnabled, !snapshotDevices.isEmpty {
            Divider()

            ForEach(snapshotDevices) { device in
                Button {
                    playOnRemoteDevice(device)
                } label: {
                    Label(
                        String(format: String(localized: "video.context.playOn %@"), device.name),
                        systemImage: device.platform.iconName
                    )
                }
            }
        }

        // Move to remote devices (only in player context where video is playing)
        if context == .player, remoteControlEnabled, !snapshotDevices.isEmpty {
            Divider()

            ForEach(snapshotDevices) { device in
                Button {
                    moveToRemoteDevice(device)
                } label: {
                    Label(
                        String(format: String(localized: "video.context.moveTo %@"), device.name),
                        systemImage: device.platform.iconName
                    )
                }
            }
        }

        Divider()

        // Video Info
        Button {
            // Dismiss player if in player context
            if context == .player {
                // Set collapsing first so mini player shows video immediately
                appEnvironment?.navigationCoordinator.isPlayerCollapsing = true
                appEnvironment?.navigationCoordinator.isPlayerExpanded = false
            }
            appEnvironment?.navigationCoordinator.navigate(to: .video(.loaded(video)))
        } label: {
            Label(String(localized: "video.context.info"), systemImage: "info.circle")
        }

        // Go to channel (hidden for media browser, or when no real channel info)
        if showGoToChannel && video.author.hasRealChannelInfo {
            Button {
                appEnvironment?.navigationCoordinator.navigateToChannel(for: video, collapsePlayer: context == .player)
            } label: {
                Label(String(localized: "video.context.goToChannel"), systemImage: "person.circle")
            }
        }

        // Add to bookmarks / Remove from bookmarks
        if showBookmarkToggle {
            Button {
                if isBookmarked {
                    appEnvironment?.dataManager.removeBookmark(for: video.id.videoID)
                } else {
                    appEnvironment?.dataManager.addBookmark(for: video)
                }
            } label: {
                if isBookmarked {
                    Label(String(localized: "video.context.removeFromBookmarks"), systemImage: "bookmark.slash")
                } else {
                    Label(String(localized: "video.context.addToBookmarks"), systemImage: "bookmark")
                }
            }
        }

        // Add to playlist
        if showAddToPlaylist {
            Button {
                showingPlaylistSheet = true
            } label: {
                Label(String(localized: "video.context.addToPlaylist"), systemImage: "text.badge.plus")
            }
        }
    }

    // MARK: - Download

    #if !os(tvOS)
    /// Starts a download either automatically or by showing the quality sheet.
    private func startDownload(for video: Video) {
        guard let appEnvironment else {
            showingDownloadSheet = true
            return
        }

        // Media source videos (SMB/WebDAV/local) use direct file URLs - no API call needed
        if video.isFromMediaSource {
            Task {
                do {
                    try await appEnvironment.downloadManager.autoEnqueueMediaSource(
                        video,
                        mediaSourcesManager: appEnvironment.mediaSourcesManager,
                        webDAVClient: appEnvironment.webDAVClient,
                        smbClient: appEnvironment.smbClient
                    )
                } catch {
                    appEnvironment.toastManager.show(
                        category: .error,
                        title: String(localized: "download.error.title"),
                        subtitle: error.localizedDescription,
                        icon: "exclamationmark.triangle",
                        iconColor: .red
                    )
                }
            }
            return
        }

        let downloadSettings = appEnvironment.downloadSettings

        // Check if auto-download mode
        if downloadSettings.preferredDownloadQuality != .ask,
           let instance = appEnvironment.instancesManager.instance(for: video) {
            Task {
                do {
                    try await appEnvironment.downloadManager.autoEnqueue(
                        video,
                        preferredQuality: downloadSettings.preferredDownloadQuality,
                        preferredAudioLanguage: appEnvironment.settingsManager.preferredAudioLanguage,
                        preferredSubtitlesLanguage: appEnvironment.settingsManager.preferredSubtitlesLanguage,
                        includeSubtitles: downloadSettings.includeSubtitlesInAutoDownload,
                        contentService: appEnvironment.contentService,
                        instance: instance
                    )
                } catch {
                    appEnvironment.toastManager.show(
                        category: .error,
                        title: String(localized: "download.error.title"),
                        subtitle: error.localizedDescription,
                        icon: "exclamationmark.triangle",
                        iconColor: .red
                    )
                }
            }
        } else {
            showingDownloadSheet = true
        }
    }
    #endif

    // MARK: - Remote Control

    /// Play a video on a remote device (from non-player context).
    /// Sends the video to play from the beginning on the remote device.
    private func playOnRemoteDevice(_ device: DiscoveredDevice) {
        LoggingService.shared.logRemoteControl("[VideoContextMenu] playOnRemoteDevice called for device: \(device.name)")
        guard let remoteControl = appEnvironment?.remoteControlCoordinator else {
            LoggingService.shared.logRemoteControlError("[VideoContextMenu] No remoteControlCoordinator available", error: nil)
            return
        }

        LoggingService.shared.logRemoteControl("[VideoContextMenu] Starting Task for remote playback")
        Task {
            LoggingService.shared.logRemoteControl("[VideoContextMenu] Task started, checking connection")
            // Connect to device if not already connected
            if !remoteControl.controllingDevices.contains(device.id) {
                LoggingService.shared.logRemoteControl("[VideoContextMenu] Connecting to device: \(device.name)")
                try? await remoteControl.connect(to: device)
            }

            // Get the appropriate instance URL for the video's content type
            let instanceURL = appEnvironment?.instancesManager.instance(for: video.id.source)?.url.absoluteString

            LoggingService.shared.logRemoteControl("[VideoContextMenu] Calling loadVideo on remoteControl")
            // Send load video command (starts from beginning, doesn't pause local since nothing is playing)
            await remoteControl.loadVideo(
                videoID: video.id.videoID,
                videoTitle: video.title,
                instanceURL: instanceURL,
                startTime: startTime,
                pauseLocalPlayback: false,
                on: device
            )
            LoggingService.shared.logRemoteControl("[VideoContextMenu] loadVideo call completed")
        }
        LoggingService.shared.logRemoteControl("[VideoContextMenu] playOnRemoteDevice returning (Task launched)")
    }

    /// Move the currently playing video to a remote device.
    /// Sends the video with current playback time and pauses local playback when remote device starts playing.
    private func moveToRemoteDevice(_ device: DiscoveredDevice) {
        guard let remoteControl = appEnvironment?.remoteControlCoordinator else { return }

        // Get current playback time from player service
        let currentTime = appEnvironment?.playerService.state.currentTime ?? 0

        Task {
            // Connect to device if not already connected
            if !remoteControl.controllingDevices.contains(device.id) {
                try? await remoteControl.connect(to: device)
            }

            // Get the appropriate instance URL for the video's content type
            let instanceURL = appEnvironment?.instancesManager.instance(for: video.id.source)?.url.absoluteString

            // Send load video command with current playback time
            // pauseLocalPlayback: true will pause local playback when remote device confirms it started playing
            await remoteControl.loadVideo(
                videoID: video.id.videoID,
                videoTitle: video.title,
                instanceURL: instanceURL,
                startTime: currentTime,
                pauseLocalPlayback: true,
                on: device
            )
        }
    }
}

// MARK: - View Extension

extension View {
    /// Attaches a video context menu with optional custom actions and context.
    ///
    /// - Parameters:
    ///   - video: The video to show the context menu for.
    ///   - customActions: Custom actions to display at the top of the menu.
    ///   - context: The view context, used to customize built-in menu items.
    ///   - startTime: Optional start time in seconds for the Play action.
    ///   - watchProgress: Optional watch progress (0-1) for the preview thumbnail.
    func videoContextMenu(
        video: Video,
        customActions: [VideoContextAction] = [],
        context: VideoContextMenuContext = .default,
        startTime: Double? = nil,
        watchProgress: Double? = nil
    ) -> some View {
        modifier(VideoContextMenuModifier(
            video: video,
            customActions: customActions,
            context: context,
            startTime: startTime,
            watchProgress: watchProgress
        ))
    }
}

// MARK: - Dropdown Menu View

#if !os(tvOS)
/// A dropdown menu view for videos, showing context menu actions.
/// Used in player views where the video is already playing.
struct VideoContextMenuView: View {
    let video: Video
    let accentColor: Color
    var buttonSize: CGFloat = 32
    var buttonBackgroundStyle: ButtonBackgroundStyle = .none
    var theme: ControlsTheme = .dark

    @Environment(\.appEnvironment) private var appEnvironment
    @State private var showingPlaylistSheet = false
    @State private var showingDownloadSheet = false
    @State private var showingDeleteDownloadConfirmation = false
    @State private var downloadToDelete: Download?
    @State private var refreshID = UUID()

    private var frameSize: CGFloat {
        buttonBackgroundStyle.glassStyle != nil ? buttonSize * 1.15 : buttonSize
    }

    var body: some View {
        Menu {
            VideoContextMenuContent(
                video: video,
                context: .player,
                showingPlaylistSheet: $showingPlaylistSheet,
                showingDownloadSheet: $showingDownloadSheet,
                showingDeleteDownloadConfirmation: $showingDeleteDownloadConfirmation,
                downloadToDelete: $downloadToDelete,
                appEnvironment: appEnvironment
            )
        } label: {
            contextMenuLabel
        }
        .id(refreshID)
        .menuIndicator(.hidden)
        .sheet(isPresented: $showingPlaylistSheet) {
            PlaylistSelectorSheet(video: video)
        }
        .sheet(isPresented: $showingDownloadSheet) {
            DownloadQualitySheet(video: video)
        }
        .alert(String(localized: "videoInfo.download.remove.title"), isPresented: $showingDeleteDownloadConfirmation) {
            Button(String(localized: "common.cancel"), role: .cancel) {}
            Button(String(localized: "videoInfo.download.remove.confirm"), role: .destructive) {
                if let download = downloadToDelete {
                    Task {
                        await appEnvironment?.downloadManager.delete(download)
                    }
                }
            }
        } message: {
            Text(String(localized: "videoInfo.download.remove.message"))
        }
        .onReceive(NotificationCenter.default.publisher(for: .bookmarksDidChange)) { _ in
            refreshID = UUID()
        }
        .onReceive(NotificationCenter.default.publisher(for: .watchHistoryDidChange)) { _ in
            refreshID = UUID()
        }
    }

    @ViewBuilder
    private var contextMenuLabel: some View {
        if let glassStyle = buttonBackgroundStyle.glassStyle {
            Image(systemName: "ellipsis")
                .font(.title2)
                .foregroundStyle(accentColor)
                .frame(width: frameSize, height: frameSize)
                .glassBackground(glassStyle, in: .circle, fallback: .ultraThinMaterial, colorScheme: theme.colorScheme)
                .contentShape(Circle())
        } else {
            Image(systemName: "ellipsis")
                .font(.title3)
                .foregroundStyle(accentColor)
                .frame(width: buttonSize, height: buttonSize)
                .contentShape(Rectangle())
        }
    }
}
#endif
