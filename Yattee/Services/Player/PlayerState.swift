//
//  PlayerState.swift
//  Yattee
//
//  Observable state for the video player.
//

import Foundation
import AVFoundation

/// The current state of video playback.
enum PlaybackState: Equatable, Sendable {
    case idle
    case loading
    case ready
    case playing
    case paused
    case buffering
    case ended
    case failed(Error)

    static func == (lhs: PlaybackState, rhs: PlaybackState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle),
             (.loading, .loading),
             (.ready, .ready),
             (.playing, .playing),
             (.paused, .paused),
             (.buffering, .buffering),
             (.ended, .ended):
            return true
        case (.failed, .failed):
            return true // Compare errors by existence, not content
        default:
            return false
        }
    }
}

/// Retry state for stream loading.
struct RetryState: Equatable, Sendable {
    /// Current retry number (1-5), not counting initial attempt.
    let currentRetry: Int
    /// Maximum number of retries (5).
    let maxRetries: Int
    /// Whether a retry is currently in progress.
    let isRetrying: Bool
    /// Whether all retries have been exhausted.
    let exhausted: Bool

    static let idle = RetryState(currentRetry: 0, maxRetries: 5, isRetrying: false, exhausted: false)

    /// Text to display during retries (e.g., "Retrying... (1/5)").
    var displayText: String? {
        guard isRetrying, currentRetry > 0 else { return nil }
        return String(localized: "player.retry.status \(currentRetry) \(maxRetries)")
    }
}

/// Represents a queued video for playback.
struct QueuedVideo: Identifiable, Equatable, Sendable, Codable {
    let id: String
    let video: Video
    let stream: Stream?
    let audioStream: Stream?
    let captions: [Caption]
    let startTime: TimeInterval?
    let addedAt: Date
    let queueSource: QueueSource?

    init(
        video: Video,
        stream: Stream? = nil,
        audioStream: Stream? = nil,
        captions: [Caption] = [],
        startTime: TimeInterval? = nil,
        queueSource: QueueSource? = nil
    ) {
        self.id = UUID().uuidString
        self.video = video
        self.stream = stream
        self.audioStream = audioStream
        self.captions = captions
        self.startTime = startTime
        self.addedAt = Date()
        self.queueSource = queueSource
    }

    /// Internal init that preserves existing ID and addedAt (for updating streams).
    init(
        id: String,
        video: Video,
        stream: Stream?,
        audioStream: Stream?,
        captions: [Caption],
        startTime: TimeInterval?,
        addedAt: Date,
        queueSource: QueueSource?
    ) {
        self.id = id
        self.video = video
        self.stream = stream
        self.audioStream = audioStream
        self.captions = captions
        self.startTime = startTime
        self.addedAt = addedAt
        self.queueSource = queueSource
    }

    static func == (lhs: QueuedVideo, rhs: QueuedVideo) -> Bool {
        lhs.id == rhs.id
    }
}

/// Playback rate options.
enum PlaybackRate: Double, CaseIterable, Identifiable, Sendable {
    case x025 = 0.25
    case x05 = 0.5
    case x075 = 0.75
    case x1 = 1.0
    case x125 = 1.25
    case x15 = 1.5
    case x175 = 1.75
    case x2 = 2.0
    case x25 = 2.5
    case x3 = 3.0

    var id: Double { rawValue }

    var displayText: String {
        if rawValue == 1.0 {
            return String(localized: "player.playbackRate.normal")
        }
        return String(format: "%.2gx", rawValue)
    }

    /// Compact display text that always shows numeric value (e.g., "1x", "1.5x").
    /// Use this in space-constrained UI like the player pill.
    var compactDisplayText: String {
        String(format: "%.2gx", rawValue)
    }
}

/// Picture-in-Picture state.
enum PiPState: Equatable, Sendable {
    case inactive
    case active
}

/// Queue playback mode.
enum QueueMode: String, CaseIterable, Codable, Sendable {
    case normal
    case repeatAll
    case repeatOne
    case shuffle

    /// SF Symbol icon for this mode.
    var icon: String {
        switch self {
        case .normal: "list.bullet"
        case .repeatAll: "repeat"
        case .repeatOne: "repeat.1"
        case .shuffle: "shuffle"
        }
    }

    /// Localized display name.
    var displayName: String {
        switch self {
        case .normal: String(localized: "queue.mode.normal")
        case .repeatAll: String(localized: "queue.mode.repeatAll")
        case .repeatOne: String(localized: "queue.mode.repeatOne")
        case .shuffle: String(localized: "queue.mode.shuffle")
        }
    }

    /// Loads saved queue mode from UserDefaults.
    static func loadSaved() -> QueueMode {
        guard let saved = UserDefaults.standard.string(forKey: "queueMode"),
              let mode = QueueMode(rawValue: saved) else {
            return .normal
        }
        return mode
    }

    /// Saves this mode to UserDefaults.
    func save() {
        UserDefaults.standard.set(rawValue, forKey: "queueMode")
    }
}

/// Observable player state.
@MainActor
@Observable
final class PlayerState {
    // MARK: - Current Video

    /// The currently playing video.
    private(set) var currentVideo: Video?

    /// The stream being used for playback.
    private(set) var currentStream: Stream?

    /// The separate audio stream (for video-only streams).
    private(set) var currentAudioStream: Stream?

    /// Current playback state.
    private(set) var playbackState: PlaybackState = .idle

    /// Current retry state for stream loading.
    private(set) var retryState: RetryState = .idle

    // MARK: - Time & Progress

    /// Current playback time in seconds.
    var currentTime: TimeInterval = 0

    /// Total duration in seconds.
    var duration: TimeInterval = 0

    /// Buffered time in seconds.
    var bufferedTime: TimeInterval = 0

    /// Whether duration updates from the player backend should be ignored.
    /// Set to true when playing through fast endpoint where duration is known from API
    /// but file size is unknown (progressive download).
    private(set) var isDurationLockedFromAPI: Bool = false

    /// Whether the current video/stream is live.
    var isLive: Bool {
        currentVideo?.isLive == true || currentStream?.isLive == true
    }

    /// Whether SMB media playback is currently active.
    /// Used to prevent SMB directory browsing while SMB streaming is in progress,
    /// as libsmbclient has internal state conflicts when used concurrently.
    var isSMBPlaybackActive: Bool {
        guard let video = currentVideo else { return false }
        guard playbackState == .playing || playbackState == .paused || playbackState == .buffering else {
            return false
        }
        return video.id.isSMBSource
    }

    /// Progress as a fraction (0-1).
    var progress: Double {
        guard duration > 0 else { return 0 }
        return min(currentTime / duration, 1.0)
    }

    /// Formatted current time string.
    var formattedCurrentTime: String {
        // For live streams, show "LIVE" instead of time
        if isLive {
            return "LIVE"
        }
        return formatTime(currentTime)
    }

    /// Formatted duration string.
    var formattedDuration: String {
        // For live streams, show "LIVE" instead of duration
        if isLive {
            return "LIVE"
        }
        return formatTime(duration)
    }

    /// Formatted remaining time string.
    var formattedRemainingTime: String {
        "-" + formatTime(max(0, duration - currentTime))
    }

    // MARK: - Playback Settings

    /// Current playback rate.
    var rate: PlaybackRate = .x1

    /// Whether playback is muted.
    var isMuted: Bool = false

    /// Volume level (0-1).
    var volume: Float = 1.0

    // MARK: - Queue

    /// Videos queued for playback (upcoming videos only, not including current).
    private(set) var queue: [QueuedVideo] = []

    /// History of previously played videos (for going back).
    private(set) var history: [QueuedVideo] = []

    /// Maximum number of videos to keep in history.
    private let maxHistorySize = 20

    /// Whether there's a previous video in history.
    var hasPrevious: Bool {
        !history.isEmpty
    }

    /// Whether there's a next video in queue.
    /// Since queue only contains upcoming videos, we just check if it's not empty.
    var hasNext: Bool {
        !queue.isEmpty
    }

    /// Current queue playback mode.
    var queueMode: QueueMode = .loadSaved() {
        didSet {
            queueMode.save()
        }
    }

    // MARK: - SponsorBlock

    /// SponsorBlock segments for current video.
    var sponsorSegments: [SponsorBlockSegment] = []

    /// Categories to auto-skip.
    var autoSkipCategories: Set<SponsorBlockCategory> = Set(
        SponsorBlockCategory.allCases.filter { $0.defaultAutoSkip }
    )

    /// Whether SponsorBlock is enabled.
    var sponsorBlockEnabled: Bool = true

    /// Current segment being shown (for skip notification).
    var currentSegment: SponsorBlockSegment?

    // MARK: - Return YouTube Dislike

    /// Dislike count from Return YouTube Dislike API.
    var dislikeCount: Int?

    // MARK: - Picture-in-Picture

    /// Current PiP state.
    var pipState: PiPState = .inactive

    /// Whether PiP is possible.
    var isPiPPossible: Bool = false

    // MARK: - Chapters

    /// Video chapters if available.
    var chapters: [VideoChapter] = []

    /// Current chapter based on playback time.
    var currentChapter: VideoChapter? {
        chapters.last { $0.startTime <= currentTime }
    }

    // MARK: - Storyboards

    /// Available storyboards for seek preview thumbnails.
    var storyboards: [Storyboard] = []

    /// Preferred storyboard for preview (highest quality available).
    var preferredStoryboard: Storyboard? {
        storyboards.highest()
    }

    // MARK: - Video Details

    /// Video details loading state.
    var videoDetailsState: VideoDetailsLoadState = .idle

    // MARK: - Comments

    /// Preloaded comments for the current video.
    var comments: [Comment] = []

    /// Comments loading state.
    var commentsState: CommentsLoadState = .idle

    /// Continuation token for loading more comments.
    var commentsContinuation: String?

    // MARK: - UI State

    /// Whether controls are visible.
    var controlsVisible: Bool = true

    /// Whether seeking is in progress.
    var isSeeking: Bool = false

    /// Whether the video is being closed (used to hide UI before dismissal).
    var isClosingVideo: Bool = false

    /// Whether the MPV debug overlay is visible.
    var showDebugOverlay: Bool = false

    /// Whether player controls are locked (buttons/gestures disabled except settings and dismiss).
    var isControlsLocked: Bool = false

    /// Actual video track aspect ratio (width/height).
    /// nil means unknown, default to 16:9.
    var videoAspectRatio: Double?

    /// Whether the first frame of the current video has been rendered.
    /// Reset when a new video loads, set when backendDidBecomeReady is called.
    var isFirstFrameReady: Bool = false

    /// Whether the buffer is ready and playback can start smoothly.
    /// This is set after waiting for sufficient buffer before calling play().
    /// Used to keep thumbnail visible until video is truly ready to play.
    var isBufferReady: Bool = false

    /// Current buffer progress as a percentage (0-100).
    /// Updated by MPV's cache-buffering-state property during initial buffering.
    /// nil when not buffering or when using AVPlayer backend.
    var bufferProgress: Int?

    /// Whether the video is vertical (portrait orientation).
    var isVerticalVideo: Bool {
        guard let ratio = videoAspectRatio else { return false }
        return ratio < 1.0
    }

    /// Display aspect ratio for UI - falls back to 16:9 if unknown.
    var displayAspectRatio: Double {
        videoAspectRatio ?? (16.0 / 9.0)
    }

    // MARK: - Methods

    /// Updates the current video and stream.
    func setCurrentVideo(_ video: Video?, stream: Stream?, audioStream: Stream? = nil) {
        // When switching to a different video, reset time-related state to prevent
        // the old video's progress from being saved to the new video
        if video?.id != currentVideo?.id {
            dislikeCount = nil
            currentTime = 0
            duration = 0
            bufferedTime = 0
            isDurationLockedFromAPI = false
            // Reset video details state for new video
            videoDetailsState = .idle
            // Reset comments for new video
            comments = []
            commentsState = .idle
            commentsContinuation = nil
            // Reset storyboards to prevent previous video's storyboards from appearing
            storyboards = []
        }
        currentVideo = video
        currentStream = stream
        currentAudioStream = audioStream
        if video == nil {
            reset()
        }
    }

    /// Updates the current stream without changing the video.
    func updateCurrentStream(_ stream: Stream) {
        currentStream = stream
    }

    /// Updates the current audio stream without changing the video.
    func updateCurrentAudioStream(_ stream: Stream) {
        currentAudioStream = stream
    }

    /// Whether the playback has failed.
    var isFailed: Bool {
        if case .failed = playbackState { return true }
        return false
    }

    /// Error message if playback failed, nil otherwise.
    var errorMessage: String? {
        if case .failed(let error) = playbackState {
            return error.localizedDescription
        }
        return nil
    }

    /// Updates the playback state.
    func setPlaybackState(_ state: PlaybackState) {
        playbackState = state
    }

    /// Updates the retry state.
    func setRetryState(_ state: RetryState) {
        retryState = state
    }

    /// Locks duration from API metadata, preventing backend updates.
    /// Used for fast endpoint streams where MPV can't determine accurate duration
    /// because the file is being progressively downloaded.
    func lockDuration(_ duration: TimeInterval) {
        self.duration = duration
        self.isDurationLockedFromAPI = true
    }

    /// Resets player state.
    func reset() {
        currentTime = 0
        duration = 0
        bufferedTime = 0
        isDurationLockedFromAPI = false
        sponsorSegments = []
        currentSegment = nil
        dislikeCount = nil
        chapters = []
        storyboards = []
        playbackState = .idle
        retryState = .idle
        isClosingVideo = false
        videoAspectRatio = nil
        isFirstFrameReady = false
        isBufferReady = false
        bufferProgress = nil
        videoDetailsState = .idle
        comments = []
        commentsState = .idle
        commentsContinuation = nil
    }

    /// Adds a video to the end of the queue.
    func addToQueue(_ video: Video, stream: Stream? = nil, audioStream: Stream? = nil, captions: [Caption] = [], queueSource: QueueSource? = nil) {
        queue.append(QueuedVideo(video: video, stream: stream, audioStream: audioStream, captions: captions, queueSource: queueSource))
    }

    /// Adds multiple videos to the end of the queue.
    func addToQueue(_ videos: [Video], queueSource: QueueSource? = nil) {
        let queuedVideos = videos.map { QueuedVideo(video: $0, queueSource: queueSource) }
        queue.append(contentsOf: queuedVideos)
    }

    /// Inserts a video at the front of the queue (to play next).
    func insertNext(_ video: Video, stream: Stream? = nil, audioStream: Stream? = nil, captions: [Caption] = [], queueSource: QueueSource? = nil) {
        queue.insert(QueuedVideo(video: video, stream: stream, audioStream: audioStream, captions: captions, queueSource: queueSource), at: 0)
    }

    /// Removes a video from the queue at the specified index.
    func removeFromQueue(at index: Int) {
        guard index >= 0, index < queue.count else { return }
        queue.remove(at: index)
    }

    /// Removes a video from the queue by its ID.
    func removeFromQueue(id: QueuedVideo.ID) {
        queue.removeAll { $0.id == id }
    }

    /// Updates a queue item with preloaded video details and streams.
    /// Preserves the item's ID for stable SwiftUI identity.
    func updateQueueItemWithPreload(at index: Int, video: Video, stream: Stream?, audioStream: Stream?) {
        guard index >= 0 && index < queue.count else { return }
        let item = queue[index]
        queue[index] = QueuedVideo(
            id: item.id,
            video: video,
            stream: stream,
            audioStream: audioStream,
            captions: item.captions,
            startTime: item.startTime,
            addedAt: item.addedAt,
            queueSource: item.queueSource
        )
    }

    /// Moves a queue item from one position to another.
    func moveQueueItem(from sourceIndex: Int, to destinationIndex: Int) {
        guard sourceIndex >= 0, sourceIndex < queue.count,
              destinationIndex >= 0, destinationIndex <= queue.count,
              sourceIndex != destinationIndex else { return }

        let item = queue.remove(at: sourceIndex)
        let adjustedDestination = destinationIndex > sourceIndex ? destinationIndex - 1 : destinationIndex
        queue.insert(item, at: adjustedDestination)
    }

    /// Clears the queue.
    func clearQueue() {
        queue.removeAll()
    }

    /// Removes and returns the next video in queue.
    /// Since queue only contains upcoming videos, this removes the first item.
    func advanceQueue() -> QueuedVideo? {
        guard !queue.isEmpty else { return nil }
        return queue.removeFirst()
    }

    /// Removes and returns the previous video from history.
    func retreatQueue() -> QueuedVideo? {
        guard !history.isEmpty else { return nil }
        return history.removeLast()
    }

    /// Pushes a video to history (for going back later).
    /// Keeps history limited to maxHistorySize.
    func pushToHistory(_ video: QueuedVideo) {
        history.append(video)
        if history.count > maxHistorySize {
            history.removeFirst()
        }
    }

    /// Clears the playback history.
    func clearHistory() {
        history.removeAll()
    }

    /// Removes and returns a random video from queue (for shuffle mode).
    func advanceQueueShuffle() -> QueuedVideo? {
        guard !queue.isEmpty else { return nil }
        let randomIndex = Int.random(in: 0..<queue.count)
        return queue.remove(at: randomIndex)
    }

    /// Moves all history items back to queue for repeat all mode.
    /// History is cleared after moving.
    func recycleHistoryToQueue() {
        // History is ordered oldest-first, so we insert in that order
        // This puts the first played video at front of queue
        queue.insert(contentsOf: history, at: 0)
        history.removeAll()
    }

    /// Returns the next video that will be played (first in queue).
    var nextQueuedVideo: QueuedVideo? {
        queue.first
    }

    // MARK: - Private

    private func formatTime(_ time: TimeInterval) -> String {
        let totalSeconds = Int(time)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%d:%02d", minutes, seconds)
        }
    }
}

/// Represents a chapter in a video.
struct VideoChapter: Identifiable, Sendable {
    let id: UUID
    let title: String
    let startTime: TimeInterval
    let endTime: TimeInterval?
    let thumbnailURL: URL?

    init(
        id: UUID = UUID(),
        title: String,
        startTime: TimeInterval,
        endTime: TimeInterval? = nil,
        thumbnailURL: URL? = nil
    ) {
        self.id = id
        self.title = title
        self.startTime = startTime
        self.endTime = endTime
        self.thumbnailURL = thumbnailURL
    }

    /// Duration of the chapter.
    var duration: TimeInterval? {
        guard let endTime else { return nil }
        return endTime - startTime
    }

    /// Formatted start time.
    var formattedStartTime: String {
        let totalSeconds = Int(startTime)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%d:%02d", minutes, seconds)
        }
    }
}
