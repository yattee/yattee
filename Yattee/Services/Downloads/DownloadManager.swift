//
//  DownloadManager.swift
//  Yattee
//
//  Manages video downloads with background support.
//

import Foundation
import SwiftUI

#if !os(tvOS)

/// Per-video download progress for efficient SwiftUI observation.
/// Views can observe individual video progress without triggering re-renders for all videos.
struct DownloadProgressInfo: Equatable {
    var progress: Double        // 0.0 to 1.0
    var isIndeterminate: Bool   // true if total size unknown
}

/// Manages video downloads with background session support.
@Observable
@MainActor
final class DownloadManager: NSObject {
    // MARK: - Properties

    /// Active downloads (queued, downloading, paused).
    var activeDownloads: [Download] = []

    /// Completed downloads.
    var completedDownloads: [Download] = []

    /// Cached set of downloaded video IDs for O(1) lookup.
    var downloadedVideoIDs: Set<VideoID> = []

    /// Cached set of downloading (active) video IDs for O(1) lookup.
    var downloadingVideoIDs: Set<VideoID> = []

    /// Per-video download progress for efficient thumbnail observation.
    /// SwiftUI's @Observable tracks dictionary access per-key, so views only
    /// re-render when their specific video's progress changes (not all videos).
    var downloadProgressByVideo: [VideoID: DownloadProgressInfo] = [:]

    /// Total storage used by downloads in bytes.
    var storageUsed: Int64 = 0

    /// Maximum concurrent downloads (reads from settings, defaults to 2).
    var maxConcurrentDownloads: Int {
        downloadSettings?.maxConcurrentDownloads ?? 2
    }

    /// IDs of downloads that are part of the current batch (suppresses individual toasts).
    /// Downloads are added when enqueued and removed when completed, failed, or cancelled.
    var batchDownloadIDs: Set<UUID> = []

    /// Retry delays between attempts (3 delays = 4 total attempts).
    /// Matches playback retry timing for consistency.
    let retryDelays: [TimeInterval] = [1, 3, 5]

    /// Maximum retry attempts (derived from retryDelays).
    var maxRetryAttempts: Int { retryDelays.count }

    /// Minimum valid file size in bytes (files smaller than this are considered failed).
    let minimumValidFileSize: Int64 = 1024  // 1 KB

    var urlSession: URLSession!
    /// Tracks video download tasks by download ID
    var videoTasks: [UUID: URLSessionDownloadTask] = [:]
    /// Tracks audio download tasks by download ID
    var audioTasks: [UUID: URLSessionDownloadTask] = [:]
    /// Tracks caption download tasks by download ID
    var captionTasks: [UUID: URLSessionDownloadTask] = [:]
    /// Tracks active storyboard download tasks by download ID
    var storyboardTasks: [UUID: Task<Void, Never>] = [:]
    /// Tracks active thumbnail download tasks by download ID
    var thumbnailTasks: [UUID: Task<Void, Never>] = [:]

    /// Thread-safe storage for mapping task identifiers to (downloadID, phase).
    /// Accessed from URLSession delegate callbacks which run on arbitrary threads.
    let taskIDStorage = LockedStorage<[Int: (downloadID: UUID, phase: DownloadPhase)]>([:])
    /// Track previous bytes to detect resets at URLSession level
    let previousBytesStorage = LockedStorage<[Int: Int64]>([:])
    /// Track last progress update time per download to throttle UI updates (0.3s interval)
    let lastProgressUpdateStorage = LockedStorage<[UUID: Date]>([:])
    let fileManager = FileManager.default
    /// Cached downloads directory URL (created once on first access)
    private static var _cachedDownloadsDirectory: URL?
    weak var toastManager: ToastManager?
    weak var downloadSettings: DownloadSettings?

    /// Debounced save task to prevent excessive JSON encoding
    var saveTask: Task<Void, Never>?

    /// Thread-safe setter for task ID mapping.
    nonisolated func setTaskInfo(_ downloadID: UUID, phase: DownloadPhase, forTask taskID: Int) {
        taskIDStorage.write { $0[taskID] = (downloadID, phase) }
    }

    /// Thread-safe getter for task ID mapping.
    nonisolated func getTaskInfo(forTask taskID: Int) -> (downloadID: UUID, phase: DownloadPhase)? {
        taskIDStorage.read { $0[taskID] }
    }

    // MARK: - Initialization

    override init() {
        super.init()
        loadDownloads()
        // Note: Session setup and resumeInterruptedDownloads are deferred to setDownloadSettings()
        // to ensure we have the correct cellular access setting before creating the session.
    }

    private func setupSession() {
        let config = URLSessionConfiguration.background(
            withIdentifier: AppIdentifiers.downloadSession
        )
        config.isDiscretionary = false
        config.sessionSendsLaunchEvents = true

        #if os(iOS)
        let allowCellular = downloadSettings?.allowCellularDownloads ?? false
        config.allowsCellularAccess = allowCellular
        LoggingService.shared.logDownload(
            "[Downloads] Session setup",
            details: "allowsCellularAccess: \(allowCellular), hasSettings: \(downloadSettings != nil)"
        )
        #else
        config.allowsCellularAccess = true
        #endif

        urlSession = URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }

    private func resumeInterruptedDownloads() {
        // Resume any downloads that were in progress when app was terminated
        Task {
            for download in activeDownloads where download.status == .downloading {
                await startDownload(for: download.id)
            }
        }
    }

    func setToastManager(_ manager: ToastManager) {
        self.toastManager = manager
    }

    func setDownloadSettings(_ settings: DownloadSettings) {
        let isInitialSetup = self.downloadSettings == nil
        self.downloadSettings = settings
        // Invalidate old session before creating new one with correct settings
        urlSession?.invalidateAndCancel()
        setupSession()
        
        // Resume interrupted downloads only on initial setup
        if isInitialSetup {
            resumeInterruptedDownloads()
        }
    }

    #if os(iOS)
    /// Refreshes the URLSession configuration when cellular settings change.
    /// Call this after the user toggles the "Allow Downloads on Cellular" setting.
    func refreshCellularAccessSetting() {
        Task {
            await recreateSessionWithNewCellularSetting()
        }
    }

    /// Recreates the URLSession with updated cellular access setting.
    /// Properly pauses active downloads, invalidates the old session, and resumes downloads.
    private func recreateSessionWithNewCellularSetting() async {
        let allowCellular = downloadSettings?.allowCellularDownloads ?? false
        LoggingService.shared.logDownload(
            "[Downloads] Cellular setting changed",
            details: "allowCellular: \(allowCellular)"
        )

        // 1. Collect downloads that are currently downloading
        let downloadingIDs = activeDownloads
            .filter { $0.status == .downloading }
            .map { $0.id }

        // 2. Pause all active downloads (saves resume data)
        for downloadID in downloadingIDs {
            if let download = activeDownloads.first(where: { $0.id == downloadID }) {
                await pause(download)
            }
        }

        // 3. Invalidate the old session
        urlSession.invalidateAndCancel()

        // 4. Create new session with updated cellular config
        setupSession()

        LoggingService.shared.logDownload(
            "[Downloads] Session recreated",
            details: "Migrating \(downloadingIDs.count) downloads"
        )

        // 5. Mark paused downloads as queued so they restart
        for downloadID in downloadingIDs {
            if let index = activeDownloads.firstIndex(where: { $0.id == downloadID }) {
                activeDownloads[index].status = .queued
            }
        }

        saveDownloads()

        // 6. Restart downloads on new session
        await startNextDownloadIfNeeded()
    }
    #endif

    // MARK: - Auto Download

    /// Automatically enqueue a video for download using the preferred quality setting.
    /// This fetches streams, selects the best match, and starts the download without user interaction.
    ///
    /// - Parameters:
    ///   - video: The video to download
    ///   - preferredQuality: The maximum quality to download
    ///   - preferredAudioLanguage: Preferred audio language code (from playback settings)
    ///   - preferredSubtitlesLanguage: Preferred subtitles language code (from playback settings)
    ///   - includeSubtitles: Whether to include subtitles
    ///   - contentService: The content service to fetch streams
    ///   - instance: The instance to fetch from
    ///   - suppressStartToast: Whether to suppress the "download started" toast (for batch downloads)
    func autoEnqueue(
        _ video: Video,
        preferredQuality: DownloadQuality,
        preferredAudioLanguage: String?,
        preferredSubtitlesLanguage: String?,
        includeSubtitles: Bool,
        contentService: ContentService,
        instance: Instance,
        suppressStartToast: Bool = false
    ) async throws {
        // Fetch streams and captions
        let fetchedVideo: Video
        let streams: [Stream]
        let captions: [Caption]
        let storyboards: [Storyboard]

        if case .extracted(_, let originalURL) = video.id.source {
            // Extracted videos need re-extraction via /api/v1/extract
            let result = try await contentService.extractURL(originalURL, instance: instance)
            fetchedVideo = result.video
            streams = result.streams
            captions = result.captions
            storyboards = []
        } else {
            let result = try await contentService.videoWithProxyStreamsAndCaptionsAndStoryboards(
                id: video.id.videoID,
                instance: instance
            )
            fetchedVideo = result.video
            streams = result.streams
            captions = result.captions
            storyboards = result.storyboards
        }

        // Filter and select video stream
        let videoStream = selectBestVideoStream(
            from: streams,
            maxQuality: preferredQuality
        )

        guard let videoStream else {
            throw DownloadError.noStreamAvailable
        }

        // Select audio stream if needed (for video-only streams)
        var audioStream: Stream?
        if videoStream.isVideoOnly {
            audioStream = selectBestAudioStream(
                from: streams,
                preferredLanguage: preferredAudioLanguage
            )
        }

        // Select caption if enabled
        var caption: Caption?
        if includeSubtitles, let preferredSubtitlesLanguage {
            caption = selectBestCaption(
                from: captions,
                preferredLanguage: preferredSubtitlesLanguage
            )
        }

        // Get storyboard
        let storyboard = storyboards.highest()

        // Enqueue the download
        let audioCodec = videoStream.isMuxed ? videoStream.audioCodec : audioStream?.audioCodec
        let audioBitrate = videoStream.isMuxed ? nil : audioStream?.bitrate

        try await enqueue(
            fetchedVideo,
            quality: videoStream.qualityLabel,
            formatID: videoStream.format,
            streamURL: videoStream.url,
            audioStreamURL: videoStream.isVideoOnly ? audioStream?.url : nil,
            captionURL: caption?.url,
            audioLanguage: audioStream?.audioLanguage,
            captionLanguage: caption?.languageCode,
            httpHeaders: videoStream.httpHeaders,
            storyboard: storyboard,
            dislikeCount: nil,
            videoCodec: videoStream.videoCodec,
            audioCodec: audioCodec,
            videoBitrate: videoStream.bitrate,
            audioBitrate: audioBitrate,
            suppressStartToast: suppressStartToast
        )
    }

    /// Automatically enqueue a media source video (SMB/WebDAV/local) for download.
    /// Unlike autoEnqueue, this doesn't make API calls - it uses the direct file URL.
    ///
    /// - For SMB files: Downloads using libsmbclient (not URLSession) since URLSession doesn't support smb:// URLs.
    /// - For local folder files: Copies the file to the downloads directory.
    /// - For WebDAV files: Uses URLSession with HTTP/HTTPS (existing approach works).
    func autoEnqueueMediaSource(
        _ video: Video,
        mediaSourcesManager: MediaSourcesManager,
        webDAVClient: WebDAVClient,
        smbClient: SMBClient
    ) async throws {
        guard case .extracted(_, let originalURL) = video.id.source else {
            throw DownloadError.noStreamAvailable
        }

        // For SMB files: download using SMBClient (not URLSession)
        // URLSession doesn't support smb:// URLs - it only supports HTTP/HTTPS
        if video.isFromSMB {
            guard let sourceID = video.mediaSourceID,
                  let filePath = video.mediaSourceFilePath,
                  let source = mediaSourcesManager.sources.first(where: { $0.id == sourceID }) else {
                throw DownloadError.noStreamAvailable
            }

            let password = mediaSourcesManager.password(for: source)

            LoggingService.shared.logDownload(
                "[Downloads] Starting SMB download",
                details: "video: \(video.title), path: \(filePath)"
            )

            // Download using libsmbclient
            let (localURL, fileSize) = try await smbClient.downloadFileToDownloads(
                filePath: filePath,
                source: source,
                password: password,
                downloadsDirectory: downloadsDirectory()
            )

            // Create completed download record
            try await createCompletedDownload(
                video: video,
                localURL: localURL,
                fileSize: fileSize
            )
            return
        }

        // For local folder files: copy to downloads directory
        if video.isFromLocalFolder {
            LoggingService.shared.logDownload(
                "[Downloads] Copying local file",
                details: "video: \(video.title), url: \(originalURL.path)"
            )

            let localURL = try copyLocalFileToDownloads(from: originalURL)
            let fileSize = self.fileSize(at: localURL.path)

            try await createCompletedDownload(
                video: video,
                localURL: localURL,
                fileSize: fileSize
            )
            return
        }

        // For WebDAV: use URLSession (HTTP-based, existing code works)
        var authHeaders: [String: String]?

        if video.isFromWebDAV,
           let sourceID = video.mediaSourceID,
           let source = mediaSourcesManager.sources.first(where: { $0.id == sourceID }) {
            let password = mediaSourcesManager.password(for: source)
            authHeaders = await webDAVClient.authHeaders(for: source, password: password)
        }

        let fileExtension = originalURL.pathExtension.lowercased()

        try await enqueue(
            video,
            quality: "Original",
            formatID: fileExtension.isEmpty ? "video" : fileExtension,
            streamURL: originalURL,
            httpHeaders: authHeaders,
            audioCodec: "aac"  // Mark as muxed since local files typically have both tracks
        )
    }

    // MARK: - Batch Download

    /// Result of a batch download operation.
    struct BatchDownloadResult: Sendable {
        let successCount: Int
        let skippedCount: Int
        let failedVideos: [(title: String, error: String)]
    }

    /// Batch enqueue multiple videos for download.
    ///
    /// This method processes videos sequentially to avoid overwhelming the API.
    /// It skips videos that are already downloaded or downloading, and reports
    /// errors via the `onError` callback which can pause execution for user input.
    ///
    /// - Parameters:
    ///   - videos: The videos to download
    ///   - preferredQuality: Maximum quality to download
    ///   - preferredAudioLanguage: Preferred audio language code
    ///   - preferredSubtitlesLanguage: Preferred subtitles language code
    ///   - includeSubtitles: Whether to include subtitles
    ///   - contentService: The content service to fetch streams
    ///   - instance: The instance to fetch from
    ///   - onProgress: Called after each video with (current, total)
    ///   - onError: Called when a video fails, returns true to continue or false to stop
    /// - Returns: Summary of the batch operation
    func batchAutoEnqueue(
        videos: [Video],
        preferredQuality: DownloadQuality,
        preferredAudioLanguage: String?,
        preferredSubtitlesLanguage: String?,
        includeSubtitles: Bool,
        contentService: ContentService,
        instance: Instance,
        onProgress: @escaping @Sendable (Int, Int) async -> Void,
        onError: @escaping @Sendable (Video, Error) async -> Bool,
        onEnqueued: (@Sendable (UUID) async -> Void)? = nil
    ) async -> BatchDownloadResult {
        var successCount = 0
        var skippedCount = 0
        var failedVideos: [(title: String, error: String)] = []

        for (index, video) in videos.enumerated() {
            // Report progress
            await onProgress(index + 1, videos.count)

            // Skip if already downloaded or downloading
            if downloadedVideoIDs.contains(video.id) || downloadingVideoIDs.contains(video.id) {
                skippedCount += 1
                LoggingService.shared.logDownload(
                    "[Batch] Skipped: \(video.id.id)",
                    details: "Already downloaded or downloading"
                )
                continue
            }

            do {
                try await autoEnqueue(
                    video,
                    preferredQuality: preferredQuality,
                    preferredAudioLanguage: preferredAudioLanguage,
                    preferredSubtitlesLanguage: preferredSubtitlesLanguage,
                    includeSubtitles: includeSubtitles,
                    contentService: contentService,
                    instance: instance,
                    suppressStartToast: true
                )

                // Report the download ID that was just created
                if let download = activeDownloads.first(where: { $0.videoID == video.id }) {
                    await onEnqueued?(download.id)
                }

                successCount += 1
            } catch {
                LoggingService.shared.logDownload(
                    "[Batch] Failed: \(video.id.id)",
                    details: error.localizedDescription
                )
                failedVideos.append((title: video.title, error: error.localizedDescription))

                // Ask user if they want to continue
                let shouldContinue = await onError(video, error)
                if !shouldContinue {
                    LoggingService.shared.logDownload(
                        "[Batch] Stopped by user",
                        details: "After \(index + 1) of \(videos.count) videos"
                    )
                    break
                }
            }
        }

        LoggingService.shared.logDownload(
            "[Batch] Complete",
            details: "Success: \(successCount), Skipped: \(skippedCount), Failed: \(failedVideos.count)"
        )

        return BatchDownloadResult(
            successCount: successCount,
            skippedCount: skippedCount,
            failedVideos: failedVideos
        )
    }

    // MARK: - Stream Selection Helpers

    /// Selects the best video stream up to the specified quality.
    /// Respects device hardware capabilities when selecting codecs.
    private func selectBestVideoStream(
        from streams: [Stream],
        maxQuality: DownloadQuality
    ) -> Stream? {
        let maxRes = maxQuality.maxResolution

        // Filter to downloadable video streams (exclude HLS/DASH)
        let videoStreams = streams
            .filter { !$0.isAudioOnly && $0.resolution != nil }
            .filter {
                let format = StreamFormat.detect(from: $0)
                return format != .hls && format != .dash
            }
            .sorted { s1, s2 in
                // Sort by resolution (higher first), then by codec priority
                let res1 = s1.resolution ?? .p360
                let res2 = s2.resolution ?? .p360
                if res1 != res2 { return res1 > res2 }
                // Prefer muxed streams
                if s1.isMuxed != s2.isMuxed { return s1.isMuxed }
                // Then by codec quality (respecting hardware capabilities)
                return HardwareCapabilities.shared.codecPriority(for: s1.videoCodec) >
                       HardwareCapabilities.shared.codecPriority(for: s2.videoCodec)
            }

        // If maxRes is nil (best quality), return the highest quality stream
        guard let maxRes else {
            return videoStreams.first
        }

        // Find the best stream that doesn't exceed maxRes
        if let stream = videoStreams.first(where: { ($0.resolution ?? .p360) <= maxRes }) {
            return stream
        }

        // Fallback: return the lowest quality stream if all exceed maxRes
        return videoStreams.last
    }

    /// Selects the best audio stream for the preferred language.
    private func selectBestAudioStream(
        from streams: [Stream],
        preferredLanguage: String?
    ) -> Stream? {
        let audioStreams = streams.filter { $0.isAudioOnly }

        if let preferred = preferredLanguage {
            if let match = audioStreams.first(where: { ($0.audioLanguage ?? "").hasPrefix(preferred) }) {
                return match
            }
        }

        // Fallback to original audio or first available
        if let original = audioStreams.first(where: { $0.isOriginalAudio }) {
            return original
        }

        return audioStreams.first
    }

    /// Selects the best caption for the preferred language.
    private func selectBestCaption(
        from captions: [Caption],
        preferredLanguage: String
    ) -> Caption? {
        // Prefer exact match, then prefix match, then base language match
        if let exact = captions.first(where: { $0.languageCode == preferredLanguage }) {
            return exact
        }
        if let prefix = captions.first(where: { $0.languageCode.hasPrefix(preferredLanguage) || $0.baseLanguageCode == preferredLanguage }) {
            return prefix
        }
        return nil
    }

    // MARK: - Queue Management

    /// Add a video to the download queue.
    func enqueue(
        _ video: Video,
        quality: String,
        formatID: String,
        streamURL: URL,
        audioStreamURL: URL? = nil,
        captionURL: URL? = nil,
        audioLanguage: String? = nil,
        captionLanguage: String? = nil,
        httpHeaders: [String: String]? = nil,
        storyboard: Storyboard? = nil,
        dislikeCount: Int? = nil,
        priority: DownloadPriority = .normal,
        videoCodec: String? = nil,
        audioCodec: String? = nil,
        videoBitrate: Int? = nil,
        audioBitrate: Int? = nil,
        suppressStartToast: Bool = false
    ) async throws {
        // Check if already downloading
        guard !activeDownloads.contains(where: { $0.videoID == video.id }) else {
            throw DownloadError.alreadyDownloading
        }

        // Check if already downloaded
        guard !completedDownloads.contains(where: { $0.videoID == video.id }) else {
            throw DownloadError.alreadyDownloaded
        }

        let download = Download(
            video: video,
            quality: quality,
            formatID: formatID,
            streamURL: streamURL,
            audioStreamURL: audioStreamURL,
            captionURL: captionURL,
            audioLanguage: audioLanguage,
            captionLanguage: captionLanguage,
            httpHeaders: httpHeaders,
            storyboard: storyboard,
            dislikeCount: dislikeCount,
            priority: priority,
            videoCodec: videoCodec,
            audioCodec: audioCodec,
            videoBitrate: videoBitrate,
            audioBitrate: audioBitrate
        )

        activeDownloads.append(download)
        downloadingVideoIDs.insert(download.videoID)
        downloadProgressByVideo[download.videoID] = DownloadProgressInfo(progress: 0, isIndeterminate: true)
        sortQueue()
        saveDownloads()

        var details = "Quality: \(quality)"
        if audioStreamURL != nil { details += ", Audio: \(audioLanguage ?? "default")" }
        if captionURL != nil { details += ", Caption: \(captionLanguage ?? "unknown")" }
        if storyboard != nil { details += ", Storyboard: \(storyboard!.storyboardCount) sheets" }
        LoggingService.shared.logDownload("Queued: \(download.videoID.id)", details: details)

        if !suppressStartToast {
            toastManager?.show(
                category: .download,
                title: String(localized: "toast.download.started.title"),
                subtitle: video.title,
                icon: "arrow.down.circle",
                iconColor: .blue,
                autoDismissDelay: 2.0
            )
        }

        // Start download if under concurrent limit
        await startNextDownloadIfNeeded()
    }

    /// Pause a download.
    func pause(_ download: Download) async {
        guard let index = activeDownloads.firstIndex(where: { $0.id == download.id }) else {
            return
        }

        // Cancel all active tasks with resume data
        if let task = videoTasks[download.id] {
            let resumeData = await task.cancelByProducingResumeData()
            if let idx = activeDownloads.firstIndex(where: { $0.id == download.id }) {
                activeDownloads[idx].resumeData = resumeData
            }
            videoTasks.removeValue(forKey: download.id)
        }

        if let task = audioTasks[download.id] {
            let resumeData = await task.cancelByProducingResumeData()
            if let idx = activeDownloads.firstIndex(where: { $0.id == download.id }) {
                activeDownloads[idx].audioResumeData = resumeData
            }
            audioTasks.removeValue(forKey: download.id)
        }

        if let task = captionTasks[download.id] {
            task.cancel()
            captionTasks.removeValue(forKey: download.id)
        }

        if let task = storyboardTasks[download.id] {
            task.cancel()
            storyboardTasks.removeValue(forKey: download.id)
        }

        if let task = thumbnailTasks[download.id] {
            task.cancel()
            thumbnailTasks.removeValue(forKey: download.id)
        }

        activeDownloads[index].status = .paused
        saveDownloads()
        LoggingService.shared.logDownload("Paused: \(download.videoID.id)")
    }

    /// Resume a paused download.
    func resume(_ download: Download) async {
        guard let index = activeDownloads.firstIndex(where: { $0.id == download.id }),
              activeDownloads[index].status == .paused || activeDownloads[index].status == .failed else {
            return
        }

        activeDownloads[index].status = .queued
        activeDownloads[index].error = nil
        activeDownloads[index].retryCount = 0  // Reset retry count on manual resume
        saveDownloads()

        LoggingService.shared.logDownload("Resumed: \(download.videoID.id)")
        await startNextDownloadIfNeeded()
    }

    /// Cancel and remove a download.
    func cancel(_ download: Download) async {
        // Cancel all tasks
        if let task = videoTasks[download.id] {
            task.cancel()
            videoTasks.removeValue(forKey: download.id)
        }
        if let task = audioTasks[download.id] {
            task.cancel()
            audioTasks.removeValue(forKey: download.id)
        }
        if let task = captionTasks[download.id] {
            task.cancel()
            captionTasks.removeValue(forKey: download.id)
        }
        if let task = storyboardTasks[download.id] {
            task.cancel()
            storyboardTasks.removeValue(forKey: download.id)
        }

        if let task = thumbnailTasks[download.id] {
            task.cancel()
            thumbnailTasks.removeValue(forKey: download.id)
        }

        activeDownloads.removeAll { $0.id == download.id }
        downloadingVideoIDs.remove(download.videoID)
        downloadProgressByVideo.removeValue(forKey: download.videoID)

        // Remove from batch tracking if this was a batch download
        batchDownloadIDs.remove(download.id)

        // Clean up partial files
        if let path = download.localVideoPath {
            try? fileManager.removeItem(at: downloadsDirectory().appendingPathComponent(path))
        }
        if let path = download.localAudioPath {
            try? fileManager.removeItem(at: downloadsDirectory().appendingPathComponent(path))
        }
        if let path = download.localCaptionPath {
            try? fileManager.removeItem(at: downloadsDirectory().appendingPathComponent(path))
        }
        if let path = download.localStoryboardPath {
            try? fileManager.removeItem(at: downloadsDirectory().appendingPathComponent(path))
        }
        if let path = download.localThumbnailPath {
            try? fileManager.removeItem(at: downloadsDirectory().appendingPathComponent(path))
        }
        if let path = download.localChannelThumbnailPath {
            try? fileManager.removeItem(at: downloadsDirectory().appendingPathComponent(path))
        }

        saveDownloads()
        LoggingService.shared.logDownload("Cancelled: \(download.videoID.id)")

        // Start next queued download
        await startNextDownloadIfNeeded()
    }

    /// Delete a completed download.
    func delete(_ download: Download) async {
        completedDownloads.removeAll { $0.id == download.id }
        downloadedVideoIDs.remove(download.videoID)

        // Delete all associated files (video, audio, caption)
        var deletedFiles: [String] = []

        if let videoPath = download.localVideoPath {
            let videoURL = downloadsDirectory().appendingPathComponent(videoPath)
            if fileManager.fileExists(atPath: videoURL.path) {
                try? fileManager.removeItem(at: videoURL)
                deletedFiles.append("video: \(videoPath)")
            }
        }

        if let audioPath = download.localAudioPath {
            let audioURL = downloadsDirectory().appendingPathComponent(audioPath)
            if fileManager.fileExists(atPath: audioURL.path) {
                try? fileManager.removeItem(at: audioURL)
                deletedFiles.append("audio: \(audioPath)")
            }
        }

        if let captionPath = download.localCaptionPath {
            let captionURL = downloadsDirectory().appendingPathComponent(captionPath)
            if fileManager.fileExists(atPath: captionURL.path) {
                try? fileManager.removeItem(at: captionURL)
                deletedFiles.append("caption: \(captionPath)")
            }
        }

        if let storyboardPath = download.localStoryboardPath {
            let storyboardURL = downloadsDirectory().appendingPathComponent(storyboardPath)
            if fileManager.fileExists(atPath: storyboardURL.path) {
                try? fileManager.removeItem(at: storyboardURL)
                deletedFiles.append("storyboard: \(storyboardPath)")
            }
        }

        if let thumbnailPath = download.localThumbnailPath {
            let thumbnailURL = downloadsDirectory().appendingPathComponent(thumbnailPath)
            if fileManager.fileExists(atPath: thumbnailURL.path) {
                try? fileManager.removeItem(at: thumbnailURL)
                deletedFiles.append("thumbnail: \(thumbnailPath)")
            }
        }

        if let channelThumbnailPath = download.localChannelThumbnailPath {
            let channelThumbnailURL = downloadsDirectory().appendingPathComponent(channelThumbnailPath)
            if fileManager.fileExists(atPath: channelThumbnailURL.path) {
                try? fileManager.removeItem(at: channelThumbnailURL)
                deletedFiles.append("channelThumbnail: \(channelThumbnailPath)")
            }
        }

        await calculateStorageUsed()
        saveDownloads()
        LoggingService.shared.logDownload("Deleted: \(download.videoID.id)", details: deletedFiles.joined(separator: ", "))
    }

    /// Move a download in the queue.
    func moveInQueue(_ download: Download, to position: Int) async {
        guard let currentIndex = activeDownloads.firstIndex(where: { $0.id == download.id }) else {
            return
        }

        let item = activeDownloads.remove(at: currentIndex)
        let targetIndex = min(max(0, position), activeDownloads.count)
        activeDownloads.insert(item, at: targetIndex)

        saveDownloads()
    }

    // MARK: - Batch Operations

    /// Pause all active downloads.
    func pauseAll() async {
        for download in activeDownloads where download.status == .downloading {
            await pause(download)
        }
    }

    /// Resume all paused downloads.
    func resumeAll() async {
        for download in activeDownloads where download.status == .paused {
            await resume(download)
        }
    }

    /// Delete all completed downloads.
    func deleteAllCompleted() async {
        for download in completedDownloads {
            await delete(download)
        }
    }

    /// Delete downloads for videos that have been watched.
    /// - Parameter watchedVideoIDs: Set of video IDs (strings) that are considered watched.
    func deleteWatchedDownloads(watchedVideoIDs: Set<String>) async {
        let watchedDownloads = completedDownloads.filter {
            watchedVideoIDs.contains($0.videoID.videoID)
        }
        for download in watchedDownloads {
            await delete(download)
        }
    }

    // MARK: - Queries

    /// Check if a video is downloaded using cached Set for O(1) lookup.
    func isDownloaded(_ videoID: VideoID) -> Bool {
        downloadedVideoIDs.contains(videoID)
    }

    /// Check if a video is currently downloading using cached Set for O(1) lookup.
    func isDownloading(_ videoID: VideoID) -> Bool {
        downloadingVideoIDs.contains(videoID)
    }

    /// Get the download for a video if it exists.
    func download(for videoID: VideoID) -> Download? {
        completedDownloads.first { $0.videoID == videoID } ??
        activeDownloads.first { $0.videoID == videoID }
    }

    /// Get the local file URL for a completed download.
    func localURL(for videoID: VideoID) -> URL? {
        guard let download = completedDownloads.first(where: { $0.videoID == videoID }),
              let fileName = download.localVideoPath else {
            return nil
        }
        return downloadsDirectory().appendingPathComponent(fileName)
    }

    /// Resolve the full file URL for a download's local path.
    func resolveLocalURL(for download: Download) -> URL? {
        guard let fileName = download.localVideoPath else {
            return nil
        }
        return downloadsDirectory().appendingPathComponent(fileName)
    }

    /// Creates a Video and Stream for playing a downloaded video.
    /// Returns nil if the download doesn't have a valid local file.
    /// Also returns the stored dislike count, audio stream, and caption URL if available.
    func videoAndStream(for download: Download) -> (video: Video, stream: Stream, audioStream: Stream?, captionURL: URL?, dislikeCount: Int?)? {
        guard let fileURL = resolveLocalURL(for: download) else {
            LoggingService.shared.warning("[Downloads] resolveLocalURL returned nil for \(download.videoID), localVideoPath=\(download.localVideoPath ?? "nil")", category: .downloads)
            return nil
        }
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            LoggingService.shared.warning("[Downloads] Local file does not exist at \(fileURL.path) for \(download.videoID)", category: .downloads)
            return nil
        }

        let video = Video(
            id: download.videoID,
            title: download.title,
            description: download.description,
            author: Author(
                id: download.channelID,
                name: download.channelName,
                thumbnailURL: download.channelThumbnailURL,
                subscriberCount: download.channelSubscriberCount
            ),
            duration: download.duration,
            publishedAt: download.publishedAt,
            publishedText: download.publishedText,
            viewCount: download.viewCount,
            likeCount: download.likeCount,
            thumbnails: download.thumbnailURL.map { [Thumbnail(url: $0, quality: .medium)] } ?? [],
            isLive: false,
            isUpcoming: false,
            scheduledStartTime: nil
        )

        // Determine video format from file extension
        let format = fileURL.pathExtension.isEmpty ? "mp4" : fileURL.pathExtension
        let mimeType = format == "webm" ? "video/webm" : "video/mp4"

        // Parse resolution from quality string (e.g., "1080p" -> StreamResolution)
        let resolution = StreamResolution(heightLabel: download.quality)

        // If no separate audio file, this is a muxed stream - use stored or default audioCodec
        let isMuxedDownload = download.localAudioPath == nil
        let streamAudioCodec = isMuxedDownload ? (download.audioCodec ?? "aac") : nil

        let stream = Stream(
            url: fileURL,
            resolution: resolution,
            format: format,
            videoCodec: download.videoCodec,
            audioCodec: streamAudioCodec,
            bitrate: download.videoBitrate,
            fileSize: download.videoTotalBytes > 0 ? download.videoTotalBytes : nil,
            isLive: false,
            mimeType: mimeType
        )

        // Create audio stream if we have a separate audio file
        var audioStream: Stream?
        if let audioPath = download.localAudioPath {
            let audioURL = downloadsDirectory().appendingPathComponent(audioPath)
            if FileManager.default.fileExists(atPath: audioURL.path) {
                let audioFormat = audioURL.pathExtension.isEmpty ? "m4a" : audioURL.pathExtension
                let audioMimeType = audioFormat == "webm" ? "audio/webm" : "audio/mp4"
                audioStream = Stream(
                    url: audioURL,
                    resolution: nil,
                    format: audioFormat,
                    audioCodec: download.audioCodec,
                    bitrate: download.audioBitrate,
                    fileSize: download.audioTotalBytes > 0 ? download.audioTotalBytes : nil,
                    isAudioOnly: true,
                    isLive: false,
                    mimeType: audioMimeType,
                    audioLanguage: download.audioLanguage
                )
            }
        }

        // Get caption URL if we have a caption file
        var captionURL: URL?
        if let captionPath = download.localCaptionPath {
            let url = downloadsDirectory().appendingPathComponent(captionPath)
            if FileManager.default.fileExists(atPath: url.path) {
                captionURL = url
            }
        }

        return (video, stream, audioStream, captionURL, download.dislikeCount)
    }

    /// Creates a Video and Stream for playing a downloaded video by video ID.
    /// Returns nil if the video is not downloaded or the file doesn't exist.
    /// Also returns the stored dislike count, audio stream, and caption URL if available.
    func videoAndStream(for videoID: VideoID) -> (video: Video, stream: Stream, audioStream: Stream?, captionURL: URL?, dislikeCount: Int?)? {
        guard let download = completedDownloads.first(where: { $0.videoID == videoID }) else {
            return nil
        }
        return videoAndStream(for: download)
    }

    // MARK: - Private Helpers

    func sortQueue() {
        activeDownloads.sort { $0.priority.rawValue > $1.priority.rawValue }
    }

    func fileSize(at path: String) -> Int64 {
        do {
            let attrs = try fileManager.attributesOfItem(atPath: path)
            return attrs[.size] as? Int64 ?? 0
        } catch {
            return 0
        }
    }

    /// Returns the downloads directory URL (cached for performance).
    func downloadsDirectory() -> URL {
        if let cached = Self._cachedDownloadsDirectory {
            return cached
        }
        let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        let downloadsURL = documentsURL.appendingPathComponent("Downloads", isDirectory: true)
        if !fileManager.fileExists(atPath: downloadsURL.path) {
            try? fileManager.createDirectory(at: downloadsURL, withIntermediateDirectories: true)
        }
        Self._cachedDownloadsDirectory = downloadsURL
        return downloadsURL
    }

    // MARK: - Media Source Download Helpers

    /// Creates a completed download record for a file already downloaded to local storage.
    /// Used for SMB/local files that bypass URLSession.
    private func createCompletedDownload(
        video: Video,
        localURL: URL,
        fileSize: Int64
    ) async throws {
        // Check if already downloaded
        guard !completedDownloads.contains(where: { $0.videoID == video.id }) else {
            throw DownloadError.alreadyDownloaded
        }

        // Check if already downloading
        guard !activeDownloads.contains(where: { $0.videoID == video.id }) else {
            throw DownloadError.alreadyDownloading
        }

        let relativePath = localURL.lastPathComponent
        let fileExtension = localURL.pathExtension.lowercased()

        var download = Download(
            video: video,
            quality: "Original",
            formatID: fileExtension.isEmpty ? "video" : fileExtension,
            streamURL: localURL,  // Not used for completed downloads but required by init
            audioCodec: "aac"     // Mark as muxed since local files typically have both tracks
        )

        download.status = .completed
        download.localVideoPath = relativePath
        download.videoTotalBytes = fileSize
        download.videoDownloadedBytes = fileSize
        download.totalBytes = fileSize
        download.downloadedBytes = fileSize
        download.completedAt = Date()

        completedDownloads.append(download)
        downloadedVideoIDs.insert(video.id)
        await calculateStorageUsed()
        saveDownloads()

        LoggingService.shared.logDownload(
            "[Downloads] Created completed download record",
            details: "video: \(video.title), path: \(relativePath), size: \(fileSize)"
        )

        // Note: Media source downloads (SMB/local) complete synchronously during enqueue,
        // so they won't be in batchDownloadIDs by the time this runs.
        // The check is kept for consistency and future-proofing.
        if !batchDownloadIDs.contains(download.id) {
            toastManager?.show(
                category: .download,
                title: String(localized: "toast.download.completed.title"),
                subtitle: video.title,
                icon: "checkmark.circle.fill",
                iconColor: .green,
                autoDismissDelay: 2.0
            )
        }
    }

    /// Copies a local file to the downloads directory.
    /// Generates a unique filename if the destination already exists.
    private func copyLocalFileToDownloads(from sourceURL: URL) throws -> URL {
        let fileName = sourceURL.lastPathComponent
        var destURL = downloadsDirectory().appendingPathComponent(fileName)

        // Handle name collision by appending number
        destURL = uniqueDestinationURL(for: destURL)

        try fileManager.copyItem(at: sourceURL, to: destURL)

        LoggingService.shared.logDownload(
            "[Downloads] Copied local file",
            details: "from: \(sourceURL.path), to: \(destURL.path)"
        )

        return destURL
    }

    /// Generates a unique file URL by appending numbers if the file already exists.
    private func uniqueDestinationURL(for url: URL) -> URL {
        guard fileManager.fileExists(atPath: url.path) else {
            return url
        }

        let directory = url.deletingLastPathComponent()
        let baseName = url.deletingPathExtension().lastPathComponent
        let fileExtension = url.pathExtension

        var counter = 1
        var newURL = url

        while fileManager.fileExists(atPath: newURL.path) {
            let newName = fileExtension.isEmpty
                ? "\(baseName) (\(counter))"
                : "\(baseName) (\(counter)).\(fileExtension)"
            newURL = directory.appendingPathComponent(newName)
            counter += 1
        }

        return newURL
    }
}

#else
// tvOS stub - downloads not supported
@Observable
@MainActor
final class DownloadManager {
    private(set) var activeDownloads: [Download] = []
    private(set) var completedDownloads: [Download] = []
    private(set) var storageUsed: Int64 = 0
    var maxConcurrentDownloads: Int { 2 }

    func enqueue(_ video: Video, quality: String, formatID: String, streamURL: URL, audioStreamURL: URL? = nil, captionURL: URL? = nil, audioLanguage: String? = nil, captionLanguage: String? = nil, httpHeaders: [String: String]? = nil, storyboard: Storyboard? = nil, dislikeCount: Int? = nil, priority: DownloadPriority = .normal, videoCodec: String? = nil, audioCodec: String? = nil, videoBitrate: Int? = nil, audioBitrate: Int? = nil, suppressStartToast: Bool = false) async throws {
        throw DownloadError.notSupported
    }

    func autoEnqueue(_ video: Video, preferredQuality: DownloadQuality, preferredAudioLanguage: String?, preferredSubtitlesLanguage: String?, includeSubtitles: Bool, contentService: ContentService, instance: Instance, suppressStartToast: Bool = false) async throws {
        throw DownloadError.notSupported
    }

    func autoEnqueueMediaSource(_ video: Video, mediaSourcesManager: MediaSourcesManager, webDAVClient: WebDAVClient, smbClient: SMBClient) async throws {
        throw DownloadError.notSupported
    }

    func pause(_ download: Download) async {}
    func resume(_ download: Download) async {}
    func cancel(_ download: Download) async {}
    func delete(_ download: Download) async {}
    func moveInQueue(_ download: Download, to position: Int) async {}
    func pauseAll() async {}
    func resumeAll() async {}
    func deleteAllCompleted() async {}
    func calculateStorageUsed() async -> Int64 { 0 }
    func getAvailableStorage() -> Int64 { 0 }
    func deleteWatchedDownloads(watchedVideoIDs: Set<String>) async {}
    func isDownloaded(_ videoID: VideoID) -> Bool { false }
    func isDownloading(_ videoID: VideoID) -> Bool { false }
    func download(for videoID: VideoID) -> Download? { nil }
    func localURL(for videoID: VideoID) -> URL? { nil }
    func resolveLocalURL(for download: Download) -> URL? { nil }
    func videoAndStream(for download: Download) -> (video: Video, stream: Stream, audioStream: Stream?, captionURL: URL?, dislikeCount: Int?)? { nil }
    func videoAndStream(for videoID: VideoID) -> (video: Video, stream: Stream, audioStream: Stream?, captionURL: URL?, dislikeCount: Int?)? { nil }
    func setToastManager(_ manager: ToastManager) {}
    func setDownloadSettings(_ settings: DownloadSettings) {}
    func downloadsDirectory() -> URL { URL(fileURLWithPath: NSTemporaryDirectory()) }
}
#endif
