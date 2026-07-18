//
//  QueueManager.swift
//  Yattee
//
//  Manages the player queue with source tracking and continuation loading.
//

import Foundation

/// Context for media browser queue playback.
/// Stores folder info needed for on-demand stream/caption resolution.
struct MediaBrowserQueueContext: Sendable {
    let source: MediaSource
    let allFilesInFolder: [MediaFile]
    let folderPath: String
}

/// Manages the player queue with advanced features like continuation loading.
@MainActor
@Observable
final class QueueManager {
    // MARK: - Dependencies

    private let contentService: ContentService
    private weak var playerState: PlayerState?
    private weak var playerService: PlayerService?
    private weak var settingsManager: SettingsManager?
    private weak var instancesManager: InstancesManager?
    private weak var downloadManager: DownloadManager?

    // MARK: - State

    /// The current queue source for loading more items.
    private(set) var currentQueueSource: QueueSource?

    /// Display label for the current queue source (e.g., playlist title, channel name).
    private(set) var currentQueueSourceLabel: String?

    /// Whether a continuation load is in progress.
    private(set) var isLoadingMore = false

    /// The threshold for triggering proactive continuation loading.
    /// When remaining items fall to this number or below, more items are loaded.
    private let continuationThreshold = 2

    /// Context for media browser queue playback (if playing from media browser).
    private(set) var mediaBrowserContext: MediaBrowserQueueContext?

    // MARK: - Initialization

    init(contentService: ContentService) {
        self.contentService = contentService
    }

    func setPlayerState(_ state: PlayerState) {
        self.playerState = state
    }

    func setPlayerService(_ service: PlayerService) {
        self.playerService = service
    }

    func setSettingsManager(_ manager: SettingsManager) {
        self.settingsManager = manager
    }

    func setInstancesManager(_ manager: InstancesManager) {
        self.instancesManager = manager
    }

    func setDownloadManager(_ manager: DownloadManager) {
        self.downloadManager = manager
    }

    // MARK: - Queue Feature Toggle

    /// Whether the queue feature is enabled.
    var isQueueEnabled: Bool {
        settingsManager?.queueEnabled ?? true
    }

    // MARK: - Queue Operations

    /// Adds a video to the end of the queue.
    func addToQueue(_ video: Video, queueSource: QueueSource? = nil) {
        guard isQueueEnabled else { return }
        playerState?.addToQueue(video, queueSource: queueSource ?? .manual)

        // Update queue source if this is the first item or source is more specific
        if currentQueueSource == nil || queueSource != nil {
            currentQueueSource = queueSource
        }

    }

    /// Adds multiple videos to the end of the queue.
    func addToQueue(_ videos: [Video], queueSource: QueueSource? = nil) {
        guard isQueueEnabled, !videos.isEmpty else { return }
        playerState?.addToQueue(videos, queueSource: queueSource ?? .manual)

        // Update queue source
        if currentQueueSource == nil || queueSource != nil {
            currentQueueSource = queueSource
        }

    }

    /// Inserts a video to play next (after the current item).
    func playNext(_ video: Video, queueSource: QueueSource? = nil) {
        guard isQueueEnabled else { return }
        playerState?.insertNext(video, queueSource: queueSource ?? .manual)

        // Update queue source if this is the first item
        if currentQueueSource == nil {
            currentQueueSource = queueSource
        }

    }

    /// Removes a video from the queue at the specified index.
    func removeFromQueue(at index: Int) {
        playerState?.removeFromQueue(at: index)
    }

    /// Removes a video from the queue by its ID.
    func removeFromQueue(id: QueuedVideo.ID) {
        playerState?.removeFromQueue(id: id)
    }

    /// Moves a queue item from one position to another.
    func moveQueueItem(from sourceIndex: Int, to destinationIndex: Int) {
        playerState?.moveQueueItem(from: sourceIndex, to: destinationIndex)
    }

    /// Clears the entire queue.
    func clearQueue() {
        playerState?.clearQueue()
        currentQueueSource = nil
        currentQueueSourceLabel = nil
        mediaBrowserContext = nil
    }

    // MARK: - Play from List

    /// Stream info provider for downloaded content or pre-resolved streams.
    typealias StreamProvider = (Video) -> (stream: Stream?, audioStream: Stream?, captions: [Caption])?

    /// Plays a video from a list, setting up queue and history appropriately.
    /// - Parameters:
    ///   - videos: All videos in the list
    ///   - index: Index of video to play
    ///   - queueSource: Source for continuation loading
    ///   - sourceLabel: Display label for the queue source (e.g., playlist title, channel name)
    ///   - startTime: Optional start time for the video
    ///   - streamProvider: Optional closure to get stream info (for downloaded content)
    func playFromList(
        videos: [Video],
        index: Int,
        queueSource: QueueSource?,
        sourceLabel: String? = nil,
        startTime: TimeInterval? = nil,
        streamProvider: StreamProvider? = nil
    ) {
        guard isQueueEnabled, !videos.isEmpty, index >= 0, index < videos.count else {
            // If queue disabled or invalid params, just play the video directly
            if index >= 0, index < videos.count {
                let video = videos[index]
                if let provider = streamProvider, let result = provider(video) {
                    playerService?.openVideo(video, stream: result.stream!, audioStream: result.audioStream)
                } else if let startTime {
                    playerService?.openVideo(video, startTime: startTime)
                } else {
                    playerService?.openVideo(video)
                }
            }
            return
        }

        // 1. Clear queue
        clearQueue()

        // 2. Populate history with preceding videos (skip if incognito or history disabled)
        if index > 0, settingsManager?.incognitoModeEnabled != true, settingsManager?.saveWatchHistory != false {
            playerState?.clearHistory()

            for i in 0..<index {
                let video = videos[i]
                if let provider = streamProvider, let result = provider(video) {
                    let item = QueuedVideo(video: video, stream: result.stream, audioStream: result.audioStream, captions: result.captions, queueSource: queueSource)
                    playerState?.pushToHistory(item)
                } else {
                    let item = QueuedVideo(video: video, queueSource: queueSource)
                    playerState?.pushToHistory(item)
                }
            }
        }

        // 3. Queue subsequent videos
        let subsequentVideos = Array(videos.dropFirst(index + 1))
        for video in subsequentVideos {
            if let provider = streamProvider, let result = provider(video) {
                playerState?.addToQueue(video, stream: result.stream, audioStream: result.audioStream, captions: result.captions, queueSource: queueSource)
            } else {
                playerState?.addToQueue(video, queueSource: queueSource ?? .manual)
            }
        }

        // 4. Set queue source for continuation
        currentQueueSource = queueSource
        currentQueueSourceLabel = sourceLabel

        // 5. Play the video
        let videoToPlay = videos[index]
        if let provider = streamProvider, let result = provider(videoToPlay) {
            playerService?.openVideo(videoToPlay, stream: result.stream!, audioStream: result.audioStream)
        } else if let startTime {
            playerService?.openVideo(videoToPlay, startTime: startTime)
        } else {
            playerService?.openVideo(videoToPlay)
        }
    }

    // MARK: - Play from Media Browser

    /// Plays a video from a media browser folder, setting up queue with all playable files.
    /// Stream and captions are resolved on-demand when each video plays.
    /// - Parameters:
    ///   - files: All playable files in the folder (videos only, sorted)
    ///   - index: Index of the video to play
    ///   - source: The media source (WebDAV/SMB/local folder)
    ///   - allFilesInFolder: All files including subtitles (for subtitle discovery)
    func playFromMediaBrowser(
        files: [MediaFile],
        index: Int,
        source: MediaSource,
        allFilesInFolder: [MediaFile]
    ) {
        guard !files.isEmpty, index >= 0, index < files.count else { return }

        let folderPath = (files[index].path as NSString).deletingLastPathComponent
        let queueSource = QueueSource.mediaBrowser(sourceID: source.id, folderPath: folderPath)

        // If queue is disabled, just play the single video
        guard isQueueEnabled else {
            let video = files[index].toVideo()
            playerService?.openVideo(video)
            return
        }

        // 1. Clear queue
        clearQueue()

        // 2. Store media browser context for on-demand stream/caption resolution
        mediaBrowserContext = MediaBrowserQueueContext(
            source: source,
            allFilesInFolder: allFilesInFolder,
            folderPath: folderPath
        )

        // 3. Populate history with preceding files (skip if incognito or history disabled)
        if index > 0, settingsManager?.incognitoModeEnabled != true, settingsManager?.saveWatchHistory != false {
            playerState?.clearHistory()
            for i in 0..<index {
                let video = files[i].toVideo()
                let item = QueuedVideo(video: video, queueSource: queueSource)
                playerState?.pushToHistory(item)
            }
        }

        // 4. Queue subsequent files (without resolving streams yet - done on-demand)
        for file in files.dropFirst(index + 1) {
            let video = file.toVideo()
            playerState?.addToQueue(video, queueSource: queueSource)
        }

        // 5. Set queue source and label (just folder name)
        currentQueueSource = queueSource
        currentQueueSourceLabel = (folderPath as NSString).lastPathComponent

        // 6. Play the selected video
        // PlayerService will detect media browser context and resolve stream/captions on-demand
        let videoToPlay = files[index].toVideo()
        playerService?.openVideo(videoToPlay)
    }

    /// Clears the media browser context when switching to a different queue source.
    func clearMediaBrowserContext() {
        mediaBrowserContext = nil
    }

    /// Whether there are more items that can be loaded from the queue source.
    func hasMoreItems() -> Bool {
        guard let source = currentQueueSource else { return false }
        return source.supportsContinuation
    }

    /// Sets the queue source for continuation loading.
    func setQueueSource(_ source: QueueSource?) {
        currentQueueSource = source
    }

    // MARK: - Proactive Continuation Loading

    /// Called when a video starts playing to trigger proactive loading.
    /// This ensures next videos are pre-loaded before the user reaches the end of the queue,
    /// and preloads streams for the next video for seamless transitions.
    func onVideoStarted() {
        guard isQueueEnabled else { return }

        let queueCount = playerState?.queue.count ?? 0

        // Load more videos when approaching the end of the queue
        if queueCount <= continuationThreshold && hasMoreItems() && !isLoadingMore {
            Task {
                try? await loadMoreQueueItems()
            }
        }

        // Preload streams for next video
        preloadNextQueueStream()
    }

    /// Loads more items from the queue source using continuation.
    func loadMoreQueueItems() async throws {
        guard let source = currentQueueSource,
              source.supportsContinuation,
              let contentSource = source.contentSource,
              let instance = instancesManager?.instance(for: contentSource),
              !isLoadingMore else {
            return
        }

        isLoadingMore = true
        defer { isLoadingMore = false }

        do {
            let result = try await loadVideosFromSource(source, instance: instance)
            playerState?.addToQueue(result.videos, queueSource: source)

            // Update continuation token for next load
            currentQueueSource = source.withContinuation(result.continuation)
        } catch {
            // Log error but don't throw - continuation loading is best-effort
            LoggingService.shared.logPlayerError("Failed to load more queue items", error: error)
        }
    }

    // MARK: - Stream Preloading

    /// Task for current preload operation (cancellable).
    private var preloadTask: Task<Void, Never>?

    /// Preloads streams for the next video in queue for seamless transitions.
    func preloadNextQueueStream() {
        guard isQueueEnabled else { return }
        guard let playerState, let nextItem = playerState.queue.first else { return }

        // Skip if already has stream loaded
        guard nextItem.stream == nil else { return }

        // Skip preloading for media source videos (SMB, etc.) - streams are resolved locally
        guard !nextItem.video.isFromMediaSource else { return }

        // Skip preloading if video is downloaded - will use local file
        if let downloadManager,
           let download = downloadManager.download(for: nextItem.video.id),
           download.status == .completed {
            return
        }

        // Cancel any existing preload
        preloadTask?.cancel()

        preloadTask = Task {
            await performStreamPreload(for: nextItem, at: 0)
        }
    }

    private func performStreamPreload(for item: QueuedVideo, at index: Int) async {
        guard let instance = instancesManager?.instance(for: item.video) else { return }

        do {
            // Fetch streams from API
            let result = try await contentService.videoWithStreamsAndCaptions(
                id: item.video.id.videoID,
                instance: instance
            )

            // Check if cancelled or queue changed
            guard !Task.isCancelled else { return }
            guard let playerState, index < playerState.queue.count,
                  playerState.queue[index].video.id == item.video.id else { return }

            // Select best streams using PlayerService's logic
            guard let playerService else { return }
            let (stream, audioStream) = playerService.selectStreamsForPreload(from: result.streams)

            // Update queue item with full video details and preloaded streams
            playerState.updateQueueItemWithPreload(at: index, video: result.video, stream: stream, audioStream: audioStream)

        } catch {
            // Silent failure - streams will be fetched on-demand when video plays
        }
    }

    // MARK: - Source-Specific Loading

    private func loadVideosFromSource(
        _ source: QueueSource,
        instance: Instance
    ) async throws -> (videos: [Video], continuation: String?) {
        switch source {
        case .channel(let channelID, let contentSource, let continuation):
            // Determine which instance to use based on content source
            let targetInstance = instanceForContentSource(contentSource) ?? instance
            let page = try await contentService.channelVideos(
                id: channelID,
                instance: targetInstance,
                continuation: continuation
            )
            return (page.videos, page.continuation)

        case .playlist(let playlistID, let continuation):
            // For playlists, we need to fetch the playlist and get videos
            // Note: Current API doesn't support playlist continuation, so return empty
            // This can be enhanced when the API supports it
            _ = (playlistID, continuation)
            return ([], nil)

        case .search(let query, _):
            // Search uses page numbers, not continuation tokens
            // For now, we don't support search continuation in queue
            _ = query
            return ([], nil)

        case .subscriptions(let continuation):
            // Subscriptions feed continuation would require SubscriptionService access
            // For now, return empty
            _ = continuation
            return ([], nil)

        case .manual:
            // Manual entries don't have continuation
            return ([], nil)

        case .mediaBrowser:
            // Media browser folders are fully loaded, no continuation needed
            return ([], nil)
        }
    }

    private func instanceForContentSource(_ source: ContentSource) -> Instance? {
        switch source {
        case .global:
            // For global content (YouTube), use any enabled instance
            return instancesManager?.instances.first { $0.isEnabled }
        case .federated(_, let instanceURL):
            // For federated content, find matching instance
            return instancesManager?.instances.first { $0.url == instanceURL }
        case .extracted:
            // Extracted content doesn't use instances
            return nil
        }
    }
}
