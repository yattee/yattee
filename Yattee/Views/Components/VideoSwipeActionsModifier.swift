//
//  VideoSwipeActionsModifier.swift
//  Yattee
//
//  View modifier that applies configurable swipe actions to video rows.
//

import SwiftUI

#if !os(tvOS)
/// View modifier that applies user-configurable swipe actions plus fixed context-specific actions.
struct VideoSwipeActionsModifier: ViewModifier {
    @Environment(\.appEnvironment) private var appEnvironment
    @Environment(\.videoQueueContext) private var queueContext

    let video: Video
    var fixedActions: [SwipeAction] = []

    @State private var showingPlaylistSheet = false
    @State private var showingDownloadSheet = false

    func body(content: Content) -> some View {
        content
            .swipeActions(actionsArray: allActions())
            .sheet(isPresented: $showingPlaylistSheet) {
                PlaylistSelectorSheet(video: video)
            }
            .sheet(isPresented: $showingDownloadSheet) {
                DownloadQualitySheet(video: video)
            }
    }

    private var visibleActions: [VideoSwipeAction] {
        appEnvironment?.settingsManager.visibleVideoSwipeActions() ?? []
    }

    private func allActions() -> [SwipeAction] {
        var actions = visibleActions.map { swipeAction(for: $0) }
        actions.append(contentsOf: fixedActions)
        return actions
    }

    private func swipeAction(for action: VideoSwipeAction) -> SwipeAction {
        switch action {
        case .playNext:
            return SwipeAction(
                symbolImage: action.symbolImage,
                tint: action.tint,
                background: action.backgroundColor
            ) { reset in
                appEnvironment?.queueManager.playNext(video)
                reset()
            }

        case .addToQueue:
            return SwipeAction(
                symbolImage: action.symbolImage,
                tint: action.tint,
                background: action.backgroundColor
            ) { reset in
                appEnvironment?.queueManager.addToQueue(video)
                reset()
            }

        case .download:
            return downloadSwipeAction(action: action)

        case .share:
            return SwipeAction(
                symbolImage: action.symbolImage,
                tint: action.tint,
                background: action.backgroundColor
            ) { reset in
                shareVideo()
                reset()
            }

        case .videoInfo:
            return SwipeAction(
                symbolImage: action.symbolImage,
                tint: action.tint,
                background: action.backgroundColor
            ) { reset in
                appEnvironment?.navigationCoordinator.navigate(to: .video(.loaded(video)))
                reset()
            }

        case .goToChannel:
            return SwipeAction(
                symbolImage: action.symbolImage,
                tint: action.tint,
                background: action.backgroundColor
            ) { reset in
                appEnvironment?.navigationCoordinator.navigateToChannel(for: video)
                reset()
            }

        case .addToBookmarks:
            return bookmarkSwipeAction(action: action)

        case .addToPlaylist:
            return SwipeAction(
                symbolImage: action.symbolImage,
                tint: action.tint,
                background: action.backgroundColor
            ) { reset in
                showingPlaylistSheet = true
                reset()
            }

        case .markWatched:
            return watchedSwipeAction(action: action)
        }
    }

    private func downloadSwipeAction(action: VideoSwipeAction) -> SwipeAction {
        let isDownloading = appEnvironment?.downloadManager.isDownloading(video.id) ?? false
        let isDownloaded = appEnvironment?.downloadManager.isDownloaded(video.id) ?? false

        if isDownloading {
            // Cancel download
            return SwipeAction(
                symbolImage: "xmark.circle",
                tint: action.tint,
                background: .red
            ) { reset in
                if let download = appEnvironment?.downloadManager.download(for: video.id) {
                    Task {
                        await appEnvironment?.downloadManager.cancel(download)
                    }
                }
                reset()
            }
        } else if isDownloaded {
            // Already downloaded - show checkmark
            return SwipeAction(
                symbolImage: "checkmark.circle.fill",
                tint: action.tint,
                background: action.backgroundColor
            ) { reset in
                // No action - already downloaded
                reset()
            }
        } else {
            // Start download
            return SwipeAction(
                symbolImage: action.symbolImage,
                tint: action.tint,
                background: action.backgroundColor
            ) { reset in
                startDownload()
                reset()
            }
        }
    }

    private func bookmarkSwipeAction(action: VideoSwipeAction) -> SwipeAction {
        let isBookmarked = appEnvironment?.dataManager.isBookmarked(videoID: video.id.videoID) ?? false

        return SwipeAction(
            symbolImage: isBookmarked ? "bookmark.slash" : action.symbolImage,
            tint: action.tint,
            background: action.backgroundColor
        ) { reset in
            if isBookmarked {
                appEnvironment?.dataManager.removeBookmark(for: video.id.videoID)
            } else {
                appEnvironment?.dataManager.addBookmark(for: video)
            }
            reset()
        }
    }

    private func watchedSwipeAction(action: VideoSwipeAction) -> SwipeAction {
        let isWatched = appEnvironment?.dataManager.watchEntry(for: video.id.videoID)?.isFinished ?? false

        return SwipeAction(
            symbolImage: isWatched ? "eye.slash" : action.symbolImage,
            tint: action.tint,
            background: action.backgroundColor
        ) { reset in
            if isWatched {
                appEnvironment?.dataManager.markAsUnwatched(videoID: video.id.videoID)
            } else {
                appEnvironment?.dataManager.markAsWatched(video: video)
            }
            reset()
        }
    }

    private func shareVideo() {
        #if os(iOS)
        let activityVC = UIActivityViewController(
            activityItems: [video.shareURL],
            applicationActivities: nil
        )
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = windowScene.windows.first,
           let rootVC = window.rootViewController {
            // Find the top-most view controller
            var topVC = rootVC
            while let presented = topVC.presentedViewController {
                topVC = presented
            }
            topVC.present(activityVC, animated: true)
        }
        #elseif os(macOS)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(video.shareURL.absoluteString, forType: .string)
        #endif
    }

    private func startDownload() {
        guard let appEnvironment else {
            showingDownloadSheet = true
            return
        }

        // Media source videos use direct file URLs
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
}

// MARK: - View Extension

extension View {
    /// Applies user-configurable video swipe actions with optional fixed context-specific actions.
    ///
    /// - Parameters:
    ///   - video: The video to apply swipe actions for.
    ///   - fixedActions: Context-specific fixed actions (e.g., delete for history).
    ///                   These appear to the right of configurable actions.
    func videoSwipeActions(
        video: Video,
        fixedActions: [SwipeAction] = []
    ) -> some View {
        modifier(VideoSwipeActionsModifier(video: video, fixedActions: fixedActions))
    }
}
#endif
