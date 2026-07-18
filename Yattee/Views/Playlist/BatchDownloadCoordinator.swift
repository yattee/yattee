//
//  BatchDownloadCoordinator.swift
//  Yattee
//
//  Shared coordinator for batch downloading videos from playlists.
//  Used by UnifiedPlaylistDetailView for batch downloading playlist videos.
//

import SwiftUI

#if !os(tvOS)

/// Observable state for batch download operations.
@Observable
@MainActor
final class BatchDownloadCoordinator {
    // MARK: - State

    /// Whether a batch download is in progress.
    var isDownloading = false

    /// Current progress (current, total).
    var progress: (current: Int, total: Int)?

    /// Whether to show the quality picker sheet.
    var showingQualitySheet = false

    /// Whether to show the error alert.
    var showingErrorAlert = false

    /// Error info for the alert.
    var errorInfo: (videoTitle: String, errorMessage: String)?

    /// Whether to continue downloading after an error.
    private var shouldContinue = true

    /// Videos to download (set when quality sheet is shown).
    private var pendingVideos: [Video] = []

    // MARK: - Dependencies

    private weak var appEnvironment: AppEnvironment?

    // MARK: - Initialization

    init() {}

    func setEnvironment(_ environment: AppEnvironment?) {
        self.appEnvironment = environment
    }

    // MARK: - Public API

    /// Starts the download process for the given videos.
    /// Shows quality picker if needed, otherwise starts immediately.
    func startDownload(videos: [Video]) {
        guard let appEnvironment, !videos.isEmpty else { return }

        pendingVideos = videos
        let downloadSettings = appEnvironment.downloadSettings

        if downloadSettings.preferredDownloadQuality != .ask {
            // Use saved preference - start immediately
            Task {
                await performBatchDownload(
                    videos: videos,
                    quality: downloadSettings.preferredDownloadQuality,
                    includeSubtitles: downloadSettings.includeSubtitlesInAutoDownload
                )
            }
        } else {
            // Show quality picker
            showingQualitySheet = true
        }
    }

    /// Called when user confirms quality selection from the sheet.
    func confirmDownload(quality: DownloadQuality, includeSubtitles: Bool) {
        let videos = pendingVideos
        pendingVideos = []

        Task {
            await performBatchDownload(
                videos: videos,
                quality: quality,
                includeSubtitles: includeSubtitles
            )
        }
    }

    /// Called when user chooses to continue after an error.
    func continueAfterError() {
        shouldContinue = true
    }

    /// Called when user chooses to stop after an error.
    func stopAfterError() {
        shouldContinue = false
    }

    /// The number of videos pending download (for sheet display).
    var pendingVideoCount: Int {
        pendingVideos.count
    }

    // MARK: - Private Implementation

    private func performBatchDownload(
        videos: [Video],
        quality: DownloadQuality,
        includeSubtitles: Bool
    ) async {
        guard let appEnvironment,
              let firstVideo = videos.first,
              let instance = appEnvironment.instancesManager.instance(for: firstVideo) else {
            appEnvironment?.toastManager.show(
                category: .error,
                title: String(localized: "batchDownload.error.title"),
                subtitle: String(localized: "batchDownload.error.noInstance.subtitle")
            )
            return
        }

        isDownloading = true
        shouldContinue = true
        progress = nil

        // Show batch start toast
        appEnvironment.toastManager.show(
            category: .download,
            title: String(localized: "batchDownload.starting.title"),
            subtitle: String(localized: "batchDownload.starting.subtitle \(videos.count)"),
            icon: "arrow.down.circle",
            iconColor: .blue,
            autoDismissDelay: 3.0
        )

        // Capture downloadManager before closure to avoid Swift 6 concurrency warning
        let downloadManager = appEnvironment.downloadManager
        let result = await downloadManager.batchAutoEnqueue(
            videos: videos,
            preferredQuality: quality,
            preferredAudioLanguage: appEnvironment.settingsManager.preferredAudioLanguage,
            preferredSubtitlesLanguage: appEnvironment.settingsManager.preferredSubtitlesLanguage,
            includeSubtitles: includeSubtitles,
            contentService: appEnvironment.contentService,
            instance: instance,
            onProgress: { @Sendable [weak self] current, total in
                guard let self else { return }
                await MainActor.run {
                    self.progress = (current: current, total: total)
                }
            },
            onError: { [weak self] video, error in
                guard let self else { return false }

                await MainActor.run {
                    self.errorInfo = (videoTitle: video.title, errorMessage: error.localizedDescription)
                    self.showingErrorAlert = true
                }

                // Wait for user to dismiss the alert
                while await MainActor.run(body: { self.showingErrorAlert }) {
                    try? await Task.sleep(for: .milliseconds(100))
                }

                return await MainActor.run { self.shouldContinue }
            },
            onEnqueued: { @Sendable downloadID in
                // Register each download as part of the batch to suppress individual toasts.
                // Downloads are removed from batchDownloadIDs when they complete, fail, or are cancelled.
                await MainActor.run {
                    _ = downloadManager.batchDownloadIDs.insert(downloadID)
                }
            }
        )

        // Note: Don't clear batchDownloadIDs here - downloads are removed individually
        // when they complete (completeMultiFileDownload), fail (handleDownloadError),
        // or are cancelled (cancel).

        isDownloading = false
        progress = nil

        showCompletionToast(result)
    }

    private func showCompletionToast(_ result: DownloadManager.BatchDownloadResult) {
        guard let appEnvironment else { return }

        if result.failedVideos.isEmpty {
            if result.skippedCount > 0 {
                appEnvironment.toastManager.showSuccess(
                    String(localized: "batchDownload.complete.title"),
                    subtitle: String(localized: "batchDownload.complete.withSkipped.subtitle \(result.successCount) \(result.skippedCount)")
                )
            } else if result.successCount > 0 {
                appEnvironment.toastManager.showSuccess(
                    String(localized: "batchDownload.complete.title"),
                    subtitle: String(localized: "batchDownload.complete.success.subtitle \(result.successCount)")
                )
            } else {
                // All skipped
                appEnvironment.toastManager.show(
                    category: .info,
                    title: String(localized: "batchDownload.complete.skipped.title"),
                    subtitle: String(localized: "batchDownload.complete.allSkipped.subtitle")
                )
            }
        } else {
            appEnvironment.toastManager.show(
                category: .error,
                title: String(localized: "batchDownload.complete.partial.title"),
                subtitle: String(localized: "batchDownload.complete.partial.subtitle \(result.successCount) \(result.failedVideos.count)")
            )
        }
    }
}

// MARK: - View Modifier

/// View modifier that adds batch download sheet and error alert.
struct BatchDownloadModifier: ViewModifier {
    @Bindable var coordinator: BatchDownloadCoordinator

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $coordinator.showingQualitySheet) {
                BatchDownloadQualitySheet(videoCount: coordinator.pendingVideoCount) { quality, includeSubtitles in
                    coordinator.confirmDownload(quality: quality, includeSubtitles: includeSubtitles)
                }
            }
            .alert(
                String(localized: "batchDownload.error.title"),
                isPresented: $coordinator.showingErrorAlert,
                presenting: coordinator.errorInfo
            ) { _ in
                Button(String(localized: "batchDownload.error.continue")) {
                    coordinator.continueAfterError()
                }
                Button(String(localized: "batchDownload.error.stop"), role: .destructive) {
                    coordinator.stopAfterError()
                }
            } message: { info in
                Text("batchDownload.error.message \(info.videoTitle) \(info.errorMessage)")
            }
    }
}

extension View {
    /// Adds batch download capability to a view.
    func batchDownload(coordinator: BatchDownloadCoordinator) -> some View {
        modifier(BatchDownloadModifier(coordinator: coordinator))
    }
}

#endif
