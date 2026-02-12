//
//  PlayerService.swift
//  Yattee
//
//  Service managing video playback with pluggable backends.
//

import Foundation
import AVFoundation
import Combine
import SwiftUI

/// Protocol for player service delegate callbacks.
@MainActor
protocol PlayerServiceDelegate: AnyObject {
    func playerService(_ service: PlayerService, didUpdateTime time: TimeInterval)
    func playerService(_ service: PlayerService, didChangeState state: PlaybackState)
    func playerService(_ service: PlayerService, didEncounterError error: Error)
    func playerService(_ service: PlayerService, shouldSkipSegment segment: SponsorBlockSegment) -> Bool
    func playerServiceDidFinishPlaying(_ service: PlayerService)
}

/// Main service for video playback.
@MainActor
@Observable
final class PlayerService {
    // MARK: - Properties

    /// The current player backend.
    private(set) var currentBackend: (any PlayerBackend)?

    /// The type of backend currently in use.
    var currentBackendType: PlayerBackendType {
        currentBackend?.backendType ?? preferredBackendType
    }

    /// MPV version information (available when MPV backend is initialized).
    var mpvVersionInfo: MPVVersionInfo? {
        (currentBackend as? MPVBackend)?.versionInfo
    }

    /// User's preferred backend type (reads directly from settings for live updates).
    var preferredBackendType: PlayerBackendType {
        settingsManager?.preferredBackend ?? .mpv
    }

    /// Observable player state.
    let state: PlayerState

    /// Delegate for callbacks.
    weak var delegate: PlayerServiceDelegate?

    /// Available streams for the current video.
    private(set) var availableStreams: [Stream] = []

    /// Available captions for the current video.
    private(set) var availableCaptions: [Caption] = []

    /// Currently loaded caption.
    private(set) var currentCaption: Caption?

    /// The current download being played, if any.
    private(set) var currentDownload: Download?

    /// Whether we're currently playing downloaded content.
    var isPlayingDownloadedContent: Bool {
        currentDownload != nil
    }

    /// Whether online streams are currently being loaded.
    private(set) var isLoadingOnlineStreams: Bool = false

    // MARK: - Dependencies

    private let httpClient: HTTPClient
    private let contentService: ContentService
    private let sponsorBlockAPI: SponsorBlockAPI
    private let returnYouTubeDislikeAPI: ReturnYouTubeDislikeAPI
    private let dataManager: DataManager
    private let backendFactory: BackendFactory
    private let backendSwitcher: BackendSwitcher
    private weak var settingsManager: SettingsManager?
    private weak var downloadManager: DownloadManager?
    private weak var navigationCoordinator: NavigationCoordinator?
    private weak var connectivityMonitor: ConnectivityMonitor?
    private weak var toastManager: ToastManager?
    private weak var queueManager: QueueManager?
    private weak var playerControlsLayoutService: PlayerControlsLayoutService?
    private weak var handoffManager: HandoffManager?

    // MARK: - Private State

    /// Current scene phase, updated by handleScenePhase
    private var currentScenePhase: ScenePhase = .active

    private var progressSaveTimer: Timer?
    private let progressSaveInterval: TimeInterval = 5

    /// Now Playing service for Control Center/Lock Screen.
    private let nowPlayingService = NowPlayingService()

    /// Service to prevent system sleep during playback.
    private let sleepPreventionService = SleepPreventionService()

    /// Tracks the last skipped segment to prevent duplicate skips.
    private var lastSkippedSegmentID: String?

    /// Tracks if the current video ended naturally (reached EOF).
    /// Used to prevent saving progress when switching to next video after natural completion.
    private var videoEndedNaturally = false

    /// Current playback task - cancelled when video is closed or new video is opened.
    private var currentPlayTask: Task<Void, Never>?

    /// Video ID that we're currently loading - used to ignore stale time updates from previous video.
    private var loadingVideoID: VideoID?

    /// Counter for stream refresh attempts to prevent infinite refresh loops.
    private var streamRefreshAttempts = 0
    private let maxStreamRefreshAttempts = 2

    /// Tracks if playback was interrupted by system (phone call, alarm, etc.)
    /// Used to auto-resume when interruption ends.
    private var wasInterrupted = false

    /// Tracks if audio session interruption observer has been registered.
    private var hasRegisteredInterruptionObserver = false

    // MARK: - Initialization

    init(
        httpClient: HTTPClient,
        contentService: ContentService,
        dataManager: DataManager,
        backendFactory: BackendFactory? = nil
    ) {
        self.httpClient = httpClient
        self.contentService = contentService
        self.dataManager = dataManager
        self.sponsorBlockAPI = SponsorBlockAPI(httpClient: httpClient)
        self.returnYouTubeDislikeAPI = ReturnYouTubeDislikeAPI(httpClient: httpClient)
        self.state = PlayerState()

        let factory = backendFactory ?? BackendFactory()
        self.backendFactory = factory
        // Note: settingsManager is set later via setSettingsManager, backendSwitcher will use it once available
        self.backendSwitcher = BackendSwitcher(backendFactory: factory, settingsManager: nil)

        // Link now playing service back to player
        nowPlayingService.playerService = self

        // Pre-warm backends asynchronously (non-blocking)
        // This starts OpenGL initialization in background immediately at app launch
        Task {
            await factory.prewarmAllBackends()
        }

        // Listen for memory warnings to drain backend pool
        #if os(iOS) || os(tvOS)
        NotificationCenter.default.addObserver(
            forName: .memoryWarning,
            object: nil,
            queue: .main
        ) { [weak factory] _ in
            Task { @MainActor [weak factory] in
                factory?.drainPool()
            }
        }
        #endif
    }

    deinit {
        MainActor.assumeIsolated {
            cleanup()
        }
    }

    // MARK: - Public Methods

    /// Prepares a video for playback without loading streams.
    /// Shows the video in the player with a play button overlay.
    /// Call `play(video:)` to actually start loading and playing.
    /// - Parameter video: The video to prepare
    func prepare(video: Video) {
        LoggingService.shared.logPlayer("Preparing video: \(video.id.id)")

        // Clear streams
        availableStreams = []

        // Set video in state but keep idle (not loading)
        state.setCurrentVideo(video, stream: nil)
        state.setPlaybackState(.idle)
    }

    /// Plays a video with optional starting time.
    /// - Parameters:
    ///   - video: The video to play
    ///   - stream: Optional specific stream to use (if provided, skips fetching streams from API)
    ///   - audioStream: Optional separate audio stream (for video-only streams)
    ///   - startTime: Optional start time in seconds
    func play(video: Video, stream: Stream? = nil, audioStream: Stream? = nil, startTime: TimeInterval? = nil) async {

        // Set up audio session when playback actually starts (not at app launch)
        setupAudioSession()

        // Save progress and sync for previous video before switching
        // Skip if video ended naturally - 100% was already saved in backendDidFinishPlaying
        if state.currentVideo != nil && state.currentVideo?.id != video.id && !videoEndedNaturally {
            saveProgressAndSync()
        }

        // Reset flag for the new video
        videoEndedNaturally = false

        // Clear sponsor block state from previous video
        state.sponsorSegments = []
        state.currentSegment = nil
        lastSkippedSegmentID = nil

        // Reset stream refresh counter for new video
        streamRefreshAttempts = 0

        // Clear caption state from previous video
        // (will be set later if this video has captions)
        currentCaption = nil
        availableCaptions = []

        // Mark that we're loading this video - time updates will be ignored until loading completes
        loadingVideoID = video.id

        state.setPlaybackState(.loading)
        state.isFirstFrameReady = false  // Reset until first frame of new video is rendered
        state.isBufferReady = false  // Reset until buffer is ready for smooth playback
        state.setCurrentVideo(video, stream: stream, audioStream: audioStream)

        // Start fetching SponsorBlock segments early (in parallel with stream loading)
        // so we have them ready before playback starts
        var sponsorBlockTask: Task<Void, Never>?
        if stream == nil, case .global = video.id.source, settingsManager?.sponsorBlockEnabled == true {
            sponsorBlockTask = Task {
                await fetchSponsorBlockSegments(for: video.id.videoID)
            }
        }

        do {
            let selectedStream: Stream
            let selectedAudioStream: Stream?
            let backendType: PlayerBackendType

            // If a stream is provided (e.g., local/downloaded file or quality switch), use it directly
            if let providedStream = stream {
                selectedStream = providedStream
                selectedAudioStream = audioStream
                backendType = preferredBackendType
                // Only set availableStreams if empty (preserve existing streams during quality switch)
                if availableStreams.isEmpty {
                    self.availableStreams = [providedStream]
                }
                state.setCurrentVideo(video, stream: providedStream, audioStream: audioStream)
                // Mark details as loaded since we're using the video as-is
                state.videoDetailsState = .loaded
                lockDurationIfNeeded(for: video, stream: providedStream)

                // Load local storyboard if this is a downloaded video
                if let downloadManager,
                   let download = downloadManager.download(for: video.id),
                   let storyboard = download.storyboard,
                   let storyboardPath = download.localStoryboardPath {
                    let storyboardDir = downloadManager.downloadsDirectory().appendingPathComponent(storyboardPath)
                    let localStoryboard = Storyboard.localStoryboard(from: storyboard, localDirectory: storyboardDir)
                    Task { await StoryboardService.shared.clearCache() }
                    state.storyboards = [localStoryboard]
                    LoggingService.shared.logPlayer("Loaded local storyboard for \(video.id.id)")
                }
            } else {
                // Mark that we're loading video details from API
                state.videoDetailsState = .loading

                // Fetch full video details (includes description), streams, captions, and storyboards in one API call
                let (fullVideo, streams, captions, storyboards) = try await fetchVideoStreamsAndCaptionsAndStoryboards(for: video)

                // Check for cancellation after network fetch
                try Task.checkCancellation()

                self.availableStreams = streams
                self.availableCaptions = captions

                // Update storyboards and clear cached sprite sheets
                Task { await StoryboardService.shared.clearCache() }
                state.storyboards = storyboards
                LoggingService.shared.logPlayer("Loaded \(storyboards.count) storyboards, preferred: \(state.preferredStoryboard?.width ?? 0)x\(state.preferredStoryboard?.height ?? 0)")

                // Select best stream for preferred backend
                let selection = selectStreamAndBackend(from: streams)

                guard let selected = selection.stream else {
                    throw APIError.noStreams
                }

                selectedStream = selected
                selectedAudioStream = selection.audioStream
                backendType = selection.backend

                // Update state with full video details and selected stream
                state.setCurrentVideo(fullVideo, stream: selectedStream, audioStream: selectedAudioStream)
                state.videoDetailsState = .loaded
                lockDurationIfNeeded(for: fullVideo, stream: selectedStream)

                // Notify observers that full video details are now available
                NotificationCenter.default.post(name: .videoDetailsDidLoad, object: nil)

                // Auto-load preferred subtitle if set and will use MPV backend
                if backendType == .mpv,
                   let preferredLanguage = settingsManager?.preferredSubtitlesLanguage,
                   !preferredLanguage.isEmpty {
                    // Find matching caption (will be loaded after backend is ready)
                    if let preferredCaption = captions.first(where: { caption in
                        caption.baseLanguageCode == preferredLanguage ||
                        caption.languageCode.hasPrefix(preferredLanguage)
                    }) {
                        // Store for later loading after backend is created
                        currentCaption = preferredCaption
                    }
                }
            }

            // Check for cancellation before loading stream
            try Task.checkCancellation()

            // Calculate seek time BEFORE loading to know if we need to prepare for initial seek
            // This prevents the thumbnail from hiding before the resume position is reached
            let seekTime: TimeInterval
            // Use state.duration as fallback for quality switching when video.duration might be 0
            let effectiveDuration = video.duration > 0 ? video.duration : state.duration
            let completionThreshold = effectiveDuration * 0.9
            let savedProgress = dataManager.watchProgress(for: video.id.videoID)
            LoggingService.shared.logPlayer("Replay check: savedProgress=\(savedProgress ?? -1), startTime=\(startTime ?? -1), duration=\(video.duration), threshold=\(completionThreshold)")

            if let startTime {
                // Explicit startTime provided - use it (0 means play from beginning, >0 means resume)
                // For quality switching with startTime > 0, honor the time unless video was completed
                if startTime > 0 && completionThreshold > 0 && startTime >= completionThreshold {
                    seekTime = 0  // Video was completed, start over
                } else {
                    seekTime = startTime
                }
            } else if let savedProgress, savedProgress > 0, savedProgress < completionThreshold {
                // No explicit startTime - use saved progress if video wasn't completed
                seekTime = savedProgress
            } else {
                // No saved progress or video was completed
                seekTime = 0
            }

            // Create or switch backend if needed
            let backend = try await ensureBackend(type: backendType)

            // If we're going to seek after load, tell the backend to defer ready callbacks
            // until the seek completes. This prevents showing a flash of the video at position 0
            // before jumping to the resume position.
            if seekTime > 0 {
                backend.prepareForInitialSeek()
            }

            // Apply volume based on volume mode setting from active preset
            let volumeMode: VolumeMode
            if let layoutService = playerControlsLayoutService {
                let layout = await layoutService.activeLayout()
                volumeMode = layout.globalSettings.volumeMode
            } else {
                volumeMode = GlobalLayoutSettings.cached.volumeMode
            }

            if volumeMode == .mpv {
                // In-app mode: use persisted volume
                backend.volume = settingsManager?.playerVolume ?? 1.0
                state.volume = backend.volume
            } else {
                // System mode: set MPV to max, let device control volume
                backend.volume = 1.0
                state.volume = 1.0
            }

            // Load stream
            // Pass EDL setting (MPV-specific: combines video+audio into single virtual file for unified caching)
            let useEDL = settingsManager?.mpvUseEDLStreams ?? true
            try await backend.load(stream: selectedStream, audioStream: selectedAudioStream, autoplay: false, useEDL: useEDL)

            // Check for cancellation after stream load completes
            try Task.checkCancellation()

            await backend.seek(to: seekTime, showLoading: false)

            // Wait for player sheet animation to complete before starting playback
            await navigationCoordinator?.waitForPlayerSheetAnimation()

            // Wait for SponsorBlock segments (started earlier in parallel with stream loading)
            // This ensures we have segments before playback starts, so intro skips can show loading
            await sponsorBlockTask?.value

            // Resolve chapters after SponsorBlock segments are available
            // Uses hierarchy: SponsorBlock chapters > description parsing
            let videoForChapters = state.currentVideo ?? video
            resolveChapters(for: videoForChapters)

            // Ensure audio session is active before setting Now Playing (required for tvOS MPV)
            #if os(iOS) || os(tvOS)
            if let mpvBackend = backend as? MPVBackend {
                LoggingService.shared.logPlayer("Ensuring audio session active before Now Playing setup")
                mpvBackend.ensureAudioSessionActive()
            }
            #endif

            LoggingService.shared.logPlayer("Setting up Now Playing info before backend.play()")
            // Update Now Playing info BEFORE starting playback (tvOS requires this order)
            // The system listens to the play event to trigger Now Playing display,
            // so metadata must be established before playback begins.
            let videoForNowPlaying = state.currentVideo ?? video
            nowPlayingService.updateNowPlaying(
                video: videoForNowPlaying,
                currentTime: seekTime,
                duration: videoForNowPlaying.duration,
                isPlaying: true
            )

            // Load artwork asynchronously (can happen in parallel with playback)
            // For downloaded videos, use local thumbnail if available for offline playback
            Task { [downloadManager] in
                var localThumbnailURL: URL?
                if let downloadManager,
                   let download = downloadManager.download(for: videoForNowPlaying.id),
                   let localThumbnailPath = download.localThumbnailPath {
                    localThumbnailURL = downloadManager.downloadsDirectory().appendingPathComponent(localThumbnailPath)
                }
                await nowPlayingService.loadArtwork(
                    from: videoForNowPlaying.bestThumbnail?.url,
                    localPath: localThumbnailURL
                )
            }

            // Start playback
            LoggingService.shared.logPlayer("Calling backend.play(), playbackState: \(state.playbackState)")
            loadingVideoID = nil  // Clear loading flag - time updates are now valid
            sleepPreventionService.preventSleep()

            // For MPV backend, wait for sufficient buffer before starting playback
            // This prevents the brief pause/stutter that occurs when MPV starts playing
            // before enough content is buffered
            // Skip buffer wait for local files - they don't need network buffering
            let isLocalFile = selectedStream.url.isFileURL
            if !isLocalFile, let mpvBackend = backend as? MPVBackend {
                let bufferTime = settingsManager?.mpvBufferSeconds ?? SettingsManager.defaultMpvBufferSeconds
                _ = await mpvBackend.waitForBuffer(minimumBuffer: bufferTime)
            }

            // Buffer is ready - thumbnail can now hide
            state.isBufferReady = true
            state.bufferProgress = nil  // Clear buffer progress since buffering is complete

            // Give SwiftUI time to process the isBufferReady state change and complete
            // the thumbnail fade-out animation (200ms) before audio starts playing.
            // Without this, audio may start while thumbnail is still visible.
            try? await Task.sleep(nanoseconds: 250_000_000)  // 250ms (animation is 200ms)

            backend.play()

            // Update Handoff activity for cross-device continuation
            handoffManager?.updateActivity(for: .video(.id(video.id)))

            // Fetch dislike counts for YouTube videos (only for online content)
            // Note: SponsorBlock is fetched earlier in parallel with stream loading
            // Note: Captions are now fetched together with video details and streams
            if stream == nil, case .global = video.id.source {
                await fetchReturnYouTubeDislikeCounts(for: video.id.videoID)
            }

            // Load preferred subtitle if one was selected earlier (for MPV backend)
            if let caption = currentCaption, let mpvBackend = backend as? MPVBackend {
                mpvBackend.loadCaption(caption)
                LoggingService.shared.logPlayer("Auto-loaded preferred subtitle: \(caption.displayName)")
            }

            // Start progress saving
            startProgressSaveTimer()

            // Notify queue manager that video started (for proactive continuation loading)
            notifyVideoStarted()

            LoggingService.shared.logPlayer("Playback started: \(video.id.id)", details: "Stream: \(selectedStream.qualityLabel)")

        } catch is CancellationError {
            // Load was cancelled because a new video was selected - don't report as error
            LoggingService.shared.logPlayer("Playback cancelled: \(video.id.id)")
            sleepPreventionService.allowSleep()
        } catch {
            LoggingService.shared.logPlayerError("Playback failed: \(video.id.id)", error: error)
            sleepPreventionService.allowSleep()
            state.videoDetailsState = .error
            state.setPlaybackState(.failed(error))
            delegate?.playerService(self, didEncounterError: error)

            // Auto-skip to next video if queue is not empty and player is not visible
            await handlePlaybackErrorAutoSkip()
        }
    }

    /// Pauses playback.
    /// - Parameter shouldSaveProgress: Whether to save watch progress. Set to `false` when video has
    ///   already ended (100% was saved in `backendDidFinishPlaying`).
    func pause(saveProgress shouldSaveProgress: Bool = true) {
        sleepPreventionService.allowSleep()
        currentBackend?.pause()
        state.setPlaybackState(.paused)
        if shouldSaveProgress {
            saveProgress()
        }
        nowPlayingService.updatePlaybackRate(isPlaying: false, currentTime: state.currentTime)
    }

    /// Resumes playback.
    func resume() {
        sleepPreventionService.preventSleep()
        currentBackend?.play()
        state.setPlaybackState(.playing)
        nowPlayingService.updatePlaybackRate(isPlaying: true, currentTime: state.currentTime)
    }

    /// Toggles play/pause.
    func togglePlayPause() {
        if state.playbackState == .playing {
            pause()
        } else if state.playbackState == .ended {
            // Restart from beginning when video has ended
            Task {
                await seek(to: 0)
                resume()
            }
        } else {
            resume()
        }
    }

    /// Stops playback and clears the player.
    func stop() {
        sleepPreventionService.allowSleep()

        if let video = state.currentVideo {
            LoggingService.shared.logPlayer("Stopping playback: \(video.id.id)")
        }

        // Cancel any ongoing stream loading
        currentPlayTask?.cancel()
        currentPlayTask = nil

        saveProgressAndSync()
        cleanup()

        // Clear Handoff activity
        handoffManager?.invalidateCurrentActivity()

        // Clear video first, then reset (reset clears isClosingVideo)
        state.setCurrentVideo(nil, stream: nil)
        state.reset()
        state.clearHistory()
        availableStreams = []
        availableCaptions = []
        folderFilesCache.removeAll()
        downloadedSubtitlesCache.removeAll()
        preDownloadedSubtitleFolders.removeAll()
        cleanupAllTempSubtitles()
        currentCaption = nil
        lastSkippedSegmentID = nil
        nowPlayingService.clearNowPlaying()
    }

    /// Seeks to a specific time.
    /// - Parameters:
    ///   - time: The time to seek to in seconds
    ///   - showLoading: If true, show loading state during seek (e.g., for early SponsorBlock skips)
    func seek(to time: TimeInterval, showLoading: Bool = false) async {
        state.isSeeking = true
        await currentBackend?.seek(to: time, showLoading: showLoading)
        state.isSeeking = false
        state.currentTime = time
    }

    /// Seeks forward by a duration.
    func seekForward(by seconds: TimeInterval = 10) {
        state.isSeeking = true
        let newTime = state.currentTime + seconds
        Task {
            await currentBackend?.seek(to: newTime, showLoading: false)
            state.isSeeking = false
        }
    }

    /// Seeks backward by a duration.
    func seekBackward(by seconds: TimeInterval = 10) {
        state.isSeeking = true
        let newTime = max(state.currentTime - seconds, 0)
        Task {
            await currentBackend?.seek(to: newTime, showLoading: false)
            state.isSeeking = false
        }
    }

    /// Seeks by a duration in the specified direction.
    /// - Parameters:
    ///   - seconds: Number of seconds to seek.
    ///   - direction: Direction to seek (forward or backward).
    func seek(seconds: TimeInterval, direction: SeekDirection) {
        switch direction {
        case .forward:
            seekForward(by: seconds)
        case .backward:
            seekBackward(by: seconds)
        }
    }

    /// Handles scene phase changes for background playback support.
    func handleScenePhase(_ phase: ScenePhase) {
        currentScenePhase = phase

        // Allow sleep when entering background, re-enable when returning to foreground if playing
        if phase == .background {
            sleepPreventionService.allowSleep()
        } else if phase == .active && state.playbackState == .playing {
            sleepPreventionService.preventSleep()
        }

        #if os(macOS)
        // On macOS, don't treat main window closing as background when the player window is still visible
        // The scenePhase changes to .background when the main window closes, but if the player window
        // is still open, we should continue playing video normally
        if phase == .background && ExpandedPlayerWindowManager.shared.isPresented {
            LoggingService.shared.debug("PlayerService: Ignoring background phase - player window is still visible", category: .player)
            return
        }
        #endif

        let backgroundEnabled = settingsManager?.backgroundPlaybackEnabled ?? true
        #if os(iOS)
        let isPiPActive = (currentBackend as? MPVBackend)?.isPiPActive ?? false
        #else
        let isPiPActive = false
        #endif
        currentBackend?.handleScenePhase(phase, backgroundEnabled: backgroundEnabled, isPiPActive: isPiPActive)
    }

    /// Plays the next video in queue, respecting the current queue mode.
    func playNext() async {
        // Pause without saving progress if video ended - 100% was already saved in backendDidFinishPlaying
        pause(saveProgress: state.playbackState != .ended)

        // Handle queue mode behavior
        switch state.queueMode {
        case .repeatOne:
            // Restart current video
            await seek(to: 0)
            resume()
            return

        case .repeatAll:
            // If queue is empty but we have history, recycle history back to queue
            if state.queue.isEmpty && !state.history.isEmpty {
                state.recycleHistoryToQueue()
            }
            // Fall through to normal advance behavior

        case .shuffle:
            // Pick random video from queue
            guard let next = state.advanceQueueShuffle() else { return }
            pushCurrentToHistoryIfNeeded()
            await playQueuedVideo(next)
            return

        case .normal:
            break // Use default behavior below
        }

        // Normal/repeatAll advance behavior
        guard let next = state.advanceQueue() else { return }
        pushCurrentToHistoryIfNeeded()
        await playQueuedVideo(next)
    }

    /// Pushes current video to history if not in incognito mode.
    private func pushCurrentToHistoryIfNeeded() {
        guard let currentVideo = state.currentVideo,
              settingsManager?.incognitoModeEnabled != true,
              settingsManager?.saveWatchHistory != false else { return }
        let historyItem = QueuedVideo(
            video: currentVideo,
            stream: state.currentStream,
            audioStream: state.currentAudioStream,
            startTime: state.currentTime
        )
        state.pushToHistory(historyItem)
    }

    /// Plays a queued video with its stream and caption info.
    /// Always starts from the beginning (0) since queue items should play fresh.
    /// Always prefers local downloaded content over pre-loaded network streams.
    /// For media browser videos, resolves stream and captions on-demand.
    private func playQueuedVideo(_ queuedVideo: QueuedVideo) async {
        // Check if this is a media source video needing on-demand resolution
        // Uses unified method that fetches folder contents dynamically - works from any playback source
        LoggingService.shared.debug("[SubtitleDebug] playQueuedVideo called, isFromMediaSource=\(queuedVideo.video.isFromMediaSource), videoID=\(queuedVideo.video.id.videoID)", category: .player)
        if queuedVideo.video.isFromMediaSource {
            LoggingService.shared.debug("[SubtitleDebug] Calling resolveMediaSourceStream", category: .player)

            do {
                let (stream, captions) = try await resolveMediaSourceStream(for: queuedVideo.video)
                LoggingService.shared.debug("[SubtitleDebug] resolveMediaSourceStream succeeded with \(captions.count) captions", category: .player)
                currentDownload = nil
                await play(video: queuedVideo.video, stream: stream, audioStream: nil, startTime: 0)

                // Set available captions and auto-select preferred
                if !captions.isEmpty {
                    self.availableCaptions = captions
                    if let preferred = settingsManager?.preferredSubtitlesLanguage,
                       let match = captions.first(where: { $0.baseLanguageCode == preferred || $0.languageCode.hasPrefix(preferred) }) {
                        loadCaption(match)
                    }
                }
                return
            } catch {
                LoggingService.shared.error("[SubtitleDebug] Failed to resolve media source stream: \(error.localizedDescription)", category: .player)
                // Fall through to try other methods
            }
        }

        LoggingService.shared.debug("[SubtitleDebug] Using fallback path, queuedVideo has \(queuedVideo.captions.count) pre-loaded captions", category: .player)
        // Always check for downloads first - prefer local files over pre-loaded network streams
        var playedFromDownload = false
        let videoID = queuedVideo.video.id

        if let downloadManager {
            if let download = downloadManager.download(for: videoID) {
                if download.status == .completed {
                    if let (downloadedVideo, localStream, audioStream, captionURL, dislikeCount) = downloadManager.videoAndStream(for: download) {
                        currentDownload = download
                        playedFromDownload = true
                        LoggingService.shared.debug("[Player] Playing queued video \(videoID.videoID) from local download", category: .player)
                        await play(video: downloadedVideo, stream: localStream, audioStream: audioStream, startTime: 0)
                        if let dislikeCount {
                            state.dislikeCount = dislikeCount
                        }
                        if let captionURL {
                            loadLocalCaption(url: captionURL)
                        }
                    } else {
                        LoggingService.shared.warning("[Player] Download for \(videoID.videoID) is completed but videoAndStream returned nil (local file missing?)", category: .player)
                        toastManager?.show(
                            category: .download,
                            title: String(localized: "toast.download.fileMissing.title"),
                            icon: "exclamationmark.triangle",
                            iconColor: .orange,
                            autoDismissDelay: 4.0
                        )
                    }
                } else {
                    LoggingService.shared.warning("[Player] Download found for \(videoID.videoID) but status is \(download.status) (not completed)", category: .player)
                }
            } else {
                let completed = downloadManager.completedDownloads.count
                let active = downloadManager.activeDownloads.count
                LoggingService.shared.warning("[Player] No download record found for \(videoID.videoID) (completed: \(completed), active: \(active))", category: .player)
            }
        } else {
            LoggingService.shared.warning("[Player] downloadManager is nil when trying to play \(videoID.videoID)", category: .player)
        }

        if !playedFromDownload {
            currentDownload = nil
            await play(video: queuedVideo.video, stream: queuedVideo.stream, audioStream: queuedVideo.audioStream, startTime: 0)
            // Load captions if available
            if !queuedVideo.captions.isEmpty {
                self.availableCaptions = queuedVideo.captions
                // Auto-select preferred language
                if let preferred = settingsManager?.preferredSubtitlesLanguage,
                   let match = queuedVideo.captions.first(where: { $0.baseLanguageCode == preferred || $0.languageCode.hasPrefix(preferred) }) {
                    loadCaption(match)
                }
            }
        }
    }

    /// Plays a video, preferring local downloaded content if available.
    /// If the video has been downloaded, plays the local file instead of streaming.
    /// For media browser videos, resolves stream and captions on-demand.
    /// If not downloaded, uses the provided fallback streams or fetches from API.
    /// - Parameters:
    ///   - video: The video to play
    ///   - fallbackStream: Optional stream to use if video is not downloaded
    ///   - fallbackAudioStream: Optional audio stream to use if video is not downloaded
    ///   - startTime: Optional start time in seconds
    func playPreferringDownloaded(
        video: Video,
        fallbackStream: Stream? = nil,
        fallbackAudioStream: Stream? = nil,
        startTime: TimeInterval? = nil
    ) async {
        // Check if this is a media source video needing on-demand resolution
        // Uses unified method that fetches folder contents dynamically - works from any playback source
        if video.isFromMediaSource {
            do {
                let (stream, captions) = try await resolveMediaSourceStream(for: video)
                currentDownload = nil
                await play(video: video, stream: stream, audioStream: nil, startTime: startTime)

                // Set available captions and auto-select preferred
                if !captions.isEmpty {
                    self.availableCaptions = captions
                    if let preferred = settingsManager?.preferredSubtitlesLanguage,
                       let match = captions.first(where: { $0.baseLanguageCode == preferred || $0.languageCode.hasPrefix(preferred) }) {
                        loadCaption(match)
                    }
                }
                return
            } catch {
                LoggingService.shared.error("Failed to resolve media source stream: \(error.localizedDescription)", category: .player)
                // Fall through to try other methods
            }
        }

        // Check if video is downloaded and play locally if so
        if let downloadManager,
           let download = downloadManager.download(for: video.id),
           download.status == .completed {
            if let (downloadedVideo, localStream, audioStream, captionURL, dislikeCount) = downloadManager.videoAndStream(for: download) {
                // Store the download info for later reference
                currentDownload = download
                await play(video: downloadedVideo, stream: localStream, audioStream: audioStream, startTime: startTime)
                // Restore dislike count from download (for offline playback)
                if let dislikeCount {
                    state.dislikeCount = dislikeCount
                }
                // Load caption if available, otherwise ensure subtitles are disabled
                if let captionURL {
                    loadLocalCaption(url: captionURL)
                }
                // Note: Storyboards are now loaded in play() for all downloaded videos

                // If downloaded video doesn't have full details (likeCount, viewCount), fetch them from API
                // This runs in the background so playback starts immediately from local file
                if downloadedVideo.supportsAPIStats, downloadedVideo.likeCount == nil || downloadedVideo.viewCount == nil {
                    Task {
                        await fetchAndUpdateVideoDetails(for: downloadedVideo)
                    }
                } else {
                    // Video has full details from download, notify observers
                    NotificationCenter.default.post(name: .videoDetailsDidLoad, object: nil)
                }
            } else {
                LoggingService.shared.warning("[Player] Download for \(video.id) is completed but videoAndStream returned nil (local file missing?)", category: .player)
                toastManager?.show(
                    category: .download,
                    title: String(localized: "toast.download.fileMissing.title"),
                    icon: "exclamationmark.triangle",
                    iconColor: .orange,
                    autoDismissDelay: 4.0
                )
                currentDownload = nil
                await play(video: video, stream: fallbackStream, audioStream: fallbackAudioStream, startTime: startTime)
            }
        } else {
            currentDownload = nil
            await play(video: video, stream: fallbackStream, audioStream: fallbackAudioStream, startTime: startTime)
        }
    }

    /// Checks if the given video is currently loaded in the player.
    /// - Parameter video: The video to check
    /// - Returns: `true` if the video is currently loaded (playing, paused, or buffering)
    func isCurrentlyPlaying(video: Video) -> Bool {
        guard let currentVideo = state.currentVideo else { return false }
        guard currentVideo.id == video.id else { return false }

        // Check if we have an active playback state (not idle or failed)
        switch state.playbackState {
        case .playing, .paused, .buffering, .ready, .loading:
            return true
        case .idle, .ended, .failed:
            return false
        }
    }

    /// Opens a video in the player, expanding the player sheet.
    /// If the video is already playing, just expands the player without reloading.
    /// Respects the autoplay setting - if disabled, prepares the video with a play button overlay.
    /// - Parameters:
    ///   - video: The video to open
    ///   - startTime: Optional start time in seconds (used for continue watching)
    func openVideo(_ video: Video, startTime: TimeInterval? = nil) {

        // Check if MPV PiP is active - if so, don't expand the player
        #if os(iOS)
        let mpvPiPActive = (currentBackend as? MPVBackend)?.isPiPActive ?? false
        #else
        let mpvPiPActive = false
        #endif

        // If this video is already playing, just expand the player (unless PiP is active)
        if isCurrentlyPlaying(video: video) {
            LoggingService.shared.logPlayer("Video already playing, just expanding")
            if !mpvPiPActive {
                navigationCoordinator?.expandPlayer()
            }
            return
        }

        // Cancel any previous play task before starting a new one
        currentPlayTask?.cancel()

        // Set video info before expanding so the sheet animates with content visible
        state.setPlaybackState(.loading)
        state.setCurrentVideo(video, stream: nil)

        // Expand player immediately so it opens while loading (unless PiP is active)
        if !mpvPiPActive {
            navigationCoordinator?.expandPlayer()
        }

        currentPlayTask = Task {
            await playPreferringDownloaded(video: video, startTime: startTime)
        }
    }

    /// Opens a video with a specific stream (e.g., for downloaded content or media sources).
    /// If the video is already playing, just expands the player without reloading.
    /// - Parameters:
    ///   - video: The video to open
    ///   - stream: The specific stream to use
    ///   - audioStream: Optional separate audio stream (for video-only streams)
    ///   - download: Optional download to load local storyboards and captions from
    ///   - captions: Optional array of external captions (e.g., from WebDAV subtitle files)
    func openVideo(_ video: Video, stream: Stream, audioStream: Stream? = nil, download: Download? = nil, captions: [Caption] = []) {
        // Check if MPV PiP is active - if so, don't expand the player
        #if os(iOS)
        let mpvPiPActive = (currentBackend as? MPVBackend)?.isPiPActive ?? false
        #else
        let mpvPiPActive = false
        #endif

        // If this video is already playing, just expand the player (unless PiP is active)
        if isCurrentlyPlaying(video: video) {
            if !mpvPiPActive {
                navigationCoordinator?.expandPlayer()
            }
            return
        }

        // Cancel any previous play task before starting a new one
        currentPlayTask?.cancel()

        // Set video info before expanding so the sheet animates with content visible
        state.setPlaybackState(.loading)
        state.setCurrentVideo(video, stream: stream, audioStream: audioStream)

        // Expand player immediately so it opens while loading (unless PiP is active)
        if !mpvPiPActive {
            navigationCoordinator?.expandPlayer()
        }

        // Try to look up download if not provided but playing local file
        var resolvedDownload = download
        if resolvedDownload == nil, let downloadManager {
            resolvedDownload = downloadManager.download(for: video.id)
        }

        // Store download for reference
        currentDownload = resolvedDownload

        LoggingService.shared.logPlayer("openVideo with stream called - download: \(resolvedDownload != nil ? "present" : "nil")")

        currentPlayTask = Task {
            await play(video: video, stream: stream, audioStream: audioStream)
            // Note: Storyboards are now loaded in play() for all downloaded videos

            // Load local caption if download has caption
            if let resolvedDownload,
               let captionPath = resolvedDownload.localCaptionPath,
               let downloadManager {
                let captionURL = downloadManager.downloadsDirectory().appendingPathComponent(captionPath)
                if FileManager.default.fileExists(atPath: captionURL.path) {
                    LoggingService.shared.logPlayer("Loading local caption: \(captionPath)")
                    loadLocalCaption(url: captionURL)
                }
            }

            // Set external captions (e.g., from WebDAV subtitle files)
            if !captions.isEmpty {
                LoggingService.shared.logPlayer("Setting \(captions.count) external caption(s)")
                self.availableCaptions = captions

                // Auto-select based on preferred language setting
                if let preferred = settingsManager?.preferredSubtitlesLanguage,
                   let match = captions.first(where: { $0.baseLanguageCode == preferred || $0.languageCode.hasPrefix(preferred) }) {
                    LoggingService.shared.logPlayer("Auto-selecting caption: \(match.displayName)")
                    loadCaption(match)
                }
            }
        }
    }

    /// Plays the previous video in queue.
    /// If more than 3 seconds into current video, restarts it instead.
    func playPrevious() async {
        // Pause without saving progress if video ended - 100% was already saved in backendDidFinishPlaying
        pause(saveProgress: state.playbackState != .ended)

        // If more than 3 seconds in, restart current video
        if state.currentTime > 3 {
            await seek(to: 0)
            resume()
            return
        }

        // Try to go back to previous video in history
        if let previous = state.retreatQueue() {
            // Push current video to front of queue (starts at 0 when replayed)
            if let currentVideo = state.currentVideo {
                state.insertNext(currentVideo, stream: state.currentStream, audioStream: state.currentAudioStream)
            }

            // Play the previous video, resuming from saved position
            await play(video: previous.video, stream: previous.stream, audioStream: previous.audioStream, startTime: previous.startTime)
        } else {
            // No history, just restart current video
            await seek(to: 0)
            resume()
        }
    }

    // MARK: - Stream Refresh

    /// Refreshes stream URLs and resumes playback at the specified time.
    /// Called when mid-playback failure is detected (e.g., expired stream URLs).
    private func refreshStreamsAndResume(atTime resumeTime: TimeInterval?) async {
        guard let video = state.currentVideo else {
            LoggingService.shared.logPlayerError("Cannot refresh streams: no current video")
            return
        }

        // Check if we've exceeded refresh attempts
        streamRefreshAttempts += 1
        if streamRefreshAttempts > maxStreamRefreshAttempts {
            LoggingService.shared.logPlayerError("Stream refresh failed: exceeded max attempts (\(maxStreamRefreshAttempts))")
            toastManager?.show(
                category: .playerStatus,
                title: String(localized: "toast.player.streamRefreshFailed.title"),
                icon: "exclamationmark.triangle",
                iconColor: .red,
                autoDismissDelay: 3.0
            )
            // Report error to delegate
            let error = BackendError.loadFailed("Stream refresh failed after \(maxStreamRefreshAttempts) attempts")
            delegate?.playerService(self, didEncounterError: error)
            state.setPlaybackState(.failed(error))
            return
        }

        LoggingService.shared.logPlayer("Refreshing streams (attempt \(streamRefreshAttempts)/\(maxStreamRefreshAttempts))")

        // Show toast that refresh is starting
        toastManager?.show(
            category: .playerStatus,
            title: String(localized: "toast.player.refreshingStream.title"),
            icon: "arrow.clockwise",
            iconColor: .blue,
            autoDismissDelay: 2.0
        )

        do {
            // Fetch fresh streams
            let (_, streams, captions) = try await fetchVideoStreamsAndCaptions(for: video)

            guard !streams.isEmpty else {
                throw APIError.noStreams
            }

            // Update available streams
            self.availableStreams = streams
            self.availableCaptions = captions

            // Find matching stream or best alternative
            let newStream = findMatchingStream(in: streams, preferring: state.currentStream)
            let newAudioStream: Stream?

            if newStream.isVideoOnly {
                // Find matching audio stream
                newAudioStream = findMatchingAudioStream(in: streams, preferring: state.currentAudioStream)
            } else {
                newAudioStream = nil
            }

            LoggingService.shared.logPlayer("Resuming with stream: \(newStream.qualityLabel) at \(resumeTime ?? 0)s")

            // Resume playback with fresh stream
            await play(video: video, stream: newStream, audioStream: newAudioStream, startTime: resumeTime)

            // Reset refresh counter on success
            streamRefreshAttempts = 0

            // Show success toast
            toastManager?.show(
                category: .playerStatus,
                title: String(localized: "toast.player.streamRefreshed.title"),
                icon: "checkmark.circle",
                iconColor: .green,
                autoDismissDelay: 2.0
            )

        } catch {
            LoggingService.shared.logPlayerError("Stream refresh failed", error: error)

            // If still under max attempts, the next error will trigger another refresh
            // Otherwise, show error to user
            if streamRefreshAttempts >= maxStreamRefreshAttempts {
                toastManager?.show(
                    category: .playerStatus,
                    title: String(localized: "toast.player.streamRefreshFailed.title"),
                    icon: "exclamationmark.triangle",
                    iconColor: .red,
                    autoDismissDelay: 3.0
                )
                delegate?.playerService(self, didEncounterError: error)
                state.setPlaybackState(.failed(error))
            }
        }
    }

    /// Finds a stream matching the preferred stream's quality, or the best available alternative.
    private func findMatchingStream(in streams: [Stream], preferring preferred: Stream?) -> Stream {
        let videoStreams = streams.filter { !$0.isAudioOnly }

        // If we have a preferred stream, try to match its resolution
        if let preferred, let preferredResolution = preferred.resolution {
            // First try exact resolution match
            if let exact = videoStreams.first(where: { $0.resolution == preferredResolution }) {
                return exact
            }

            // Then try closest resolution
            let sorted = videoStreams.sorted { stream1, stream2 in
                let diff1 = abs((stream1.resolution?.height ?? 0) - preferredResolution.height)
                let diff2 = abs((stream2.resolution?.height ?? 0) - preferredResolution.height)
                return diff1 < diff2
            }
            if let closest = sorted.first {
                return closest
            }
        }

        // Fall back to best available stream
        return videoStreams.max(by: { ($0.resolution?.height ?? 0) < ($1.resolution?.height ?? 0) }) ?? streams.first!
    }

    /// Finds an audio stream matching the preferred stream, or the best available alternative.
    private func findMatchingAudioStream(in streams: [Stream], preferring preferred: Stream?) -> Stream? {
        let audioStreams = streams.filter { $0.isAudioOnly }

        guard !audioStreams.isEmpty else { return nil }

        // If we have a preferred audio stream, try to match its language/codec
        if let preferred {
            // Try exact language match
            if let preferredLang = preferred.audioLanguage,
               let match = audioStreams.first(where: { $0.audioLanguage == preferredLang }) {
                return match
            }
        }

        // Fall back to best available (highest bitrate)
        return audioStreams.max(by: { ($0.bitrate ?? 0) < ($1.bitrate ?? 0) })
    }

    // MARK: - Captions

    /// Loads and displays a caption track.
    /// Only works with MPV backend.
    /// - Parameter caption: The caption to load, or nil to disable subtitles
    func loadCaption(_ caption: Caption?) {
        guard let mpvBackend = currentBackend as? MPVBackend else {
            LoggingService.shared.debug("Cannot load caption: not using MPV backend", category: .player)
            return
        }

        mpvBackend.loadCaption(caption)
        currentCaption = caption

        if let caption {
            LoggingService.shared.logPlayer("Loaded caption: \(caption.displayName)")
        } else {
            LoggingService.shared.logPlayer("Disabled subtitles")
        }
    }

    /// Loads a local subtitle file from disk.
    /// Only works with MPV backend.
    /// - Parameter url: The local file URL of the caption file
    func loadLocalCaption(url: URL) {
        // Extract language from filename (e.g., "videoID_en.vtt" -> "en")
        let filename = url.deletingPathExtension().lastPathComponent
        let languageCode = filename.components(separatedBy: "_").last ?? "unknown"
        let languageName = Locale.current.localizedString(forLanguageCode: languageCode) ?? languageCode

        let caption = Caption(
            label: languageName,
            languageCode: languageCode,
            url: url
        )

        loadCaption(caption)
    }

    /// Loads online streams for the current video (when playing downloaded content).
    /// After loading, the user can switch to an online stream from QualitySelectorView.
    /// The downloaded stream is preserved and mixed in with online streams.
    func loadOnlineStreams() async {
        guard let video = state.currentVideo else { return }

        // Keep track of current downloaded streams (local file URLs)
        let downloadedStreams = availableStreams.filter { $0.url.isFileURL }

        isLoadingOnlineStreams = true
        defer { isLoadingOnlineStreams = false }

        do {
            let (_, streams, captions) = try await fetchVideoStreamsAndCaptions(for: video)
            // Combine downloaded streams with online streams (downloaded first)
            availableStreams = downloadedStreams + streams
            availableCaptions = captions
            LoggingService.shared.logPlayer("Loaded \(streams.count) online streams and \(captions.count) captions (keeping \(downloadedStreams.count) downloaded)")
        } catch {
            LoggingService.shared.logPlayerError("Failed to load online streams", error: error)
        }
    }

    /// Switches from downloaded content to an online stream.
    /// - Parameters:
    ///   - stream: The online stream to switch to
    ///   - audioStream: Optional separate audio stream
    func switchToOnlineStream(_ stream: Stream, audioStream: Stream? = nil) async {
        guard let video = state.currentVideo else { return }

        // Clear the download flag since we're now playing online
        currentDownload = nil

        // Get current playback position to resume at
        let currentTime = state.currentTime

        // Play the new stream from the current position
        await play(video: video, stream: stream, audioStream: audioStream, startTime: currentTime)
    }

    // MARK: - Media Browser Stream Resolution

    /// Resolves stream and captions for a media browser video on-demand.
    /// - Parameters:
    ///   - video: The video to resolve
    ///   - context: Media browser context with source and folder files
    /// - Returns: Tuple of (stream, captions) ready for playback
    func resolveMediaBrowserStream(
        for video: Video,
        context: MediaBrowserQueueContext
    ) async throws -> (stream: Stream, captions: [Caption]) {
        // Find the MediaFile for this video in the folder
        // videoID format: "sourceUUID:path"
        guard let mediaFile = context.allFilesInFolder.first(where: { $0.id == video.id.videoID }) else {
            throw MediaSourceError.pathNotFound("Video file not found in folder context")
        }

        // Find matching subtitle files
        let subtitleFiles = mediaFile.findMatchingSubtitles(in: context.allFilesInFolder)

        let source = context.source
        let password = mediaSourcesManager?.password(for: source)

        switch source.type {
        case .webdav:
            // Get auth headers for WebDAV
            var authHeaders: [String: String]?
            if let webDAVClient {
                authHeaders = await webDAVClient.authHeaders(for: source, password: password)
            }
            let stream = mediaFile.toStream(authHeaders: authHeaders)
            // Subtitles can use remote URLs directly for WebDAV
            return (stream, subtitleFiles)

        case .smb:
            guard let smbClient else {
                throw MediaSourceError.unknown("SMB client not available")
            }

            let folderKey = source.id.uuidString + ":" + context.folderPath

            // Pre-download ALL subtitles in folder on first access.
            // Must complete before MPV opens any SMB connection.
            // For queued videos from the same folder, subtitles will already be cached.
            if !preDownloadedSubtitleFolders.contains(folderKey) {
                let allSubtitleFiles = context.allFilesInFolder.filter { $0.isSubtitle }
                LoggingService.shared.logMediaSources("Pre-downloading \(allSubtitleFiles.count) subtitle(s) from folder: \(context.folderPath)")

                for subtitleFile in allSubtitleFiles {
                    do {
                        let localURL = try await smbClient.downloadSubtitleToTemp(
                            file: subtitleFile,
                            source: source,
                            password: password,
                            videoID: folderKey
                        )
                        downloadedSubtitlesCache[subtitleFile.id] = localURL
                        LoggingService.shared.logMediaSources("Pre-downloaded subtitle: \(subtitleFile.name) → \(localURL.lastPathComponent)")
                    } catch {
                        LoggingService.shared.error(
                            "Failed to pre-download subtitle \(subtitleFile.name): \(error.localizedDescription)",
                            category: .general
                        )
                    }
                }

                preDownloadedSubtitleFolders.insert(folderKey)

                // Release app SMB context before MPV opens its connection.
                // libsmbclient uses process-global talloc state that corrupts
                // when two contexts access the same server concurrently.
                await smbClient.clearCache(for: source)
                LoggingService.shared.logMediaSources("Cleared SMB context cache before playback")
            }

            // Construct video playback URL (pure string manipulation, no libsmbclient)
            let playbackURL = try await smbClient.constructPlaybackURL(
                for: mediaFile,
                source: source,
                password: password
            )
            let stream = Stream(url: playbackURL, resolution: nil, format: mediaFile.fileExtension)

            // Build captions from pre-downloaded local files
            var localCaptions: [Caption] = []
            for subtitle in subtitleFiles {
                if let subtitleFile = context.allFilesInFolder.first(where: { $0.url == subtitle.url }),
                   let localURL = downloadedSubtitlesCache[subtitleFile.id] {
                    localCaptions.append(Caption(
                        label: subtitle.label,
                        languageCode: subtitle.languageCode,
                        url: localURL
                    ))
                    LoggingService.shared.info(
                        "Using pre-downloaded subtitle: \(subtitleFile.name)",
                        category: .general
                    )
                }
            }

            return (stream, localCaptions)

        case .localFolder:
            // Local folder - no auth needed, use file:// URLs directly
            let stream = mediaFile.toStream(authHeaders: nil)
            return (stream, subtitleFiles)
        }
    }

    /// Resolves stream and subtitles for a media source video by fetching folder contents on-demand.
    /// Works for all media source types (WebDAV, SMB, local folders) from any playback source
    /// (Media Browser, Continue Watching, etc.).
    func resolveMediaSourceStream(for video: Video) async throws -> (stream: Stream, captions: [Caption]) {
        LoggingService.shared.debug("[SubtitleDebug] resolveMediaSourceStream called for videoID: \(video.id.videoID)", category: .player)

        // 1. Extract source ID and file path from video ID
        guard let sourceID = video.mediaSourceID,
              let filePath = video.mediaSourceFilePath else {
            LoggingService.shared.error("[SubtitleDebug] Failed to extract source info - mediaSourceID: \(String(describing: video.mediaSourceID)), mediaSourceFilePath: \(String(describing: video.mediaSourceFilePath))", category: .player)
            throw MediaSourceError.pathNotFound("Could not extract source info from video ID")
        }

        LoggingService.shared.debug("[SubtitleDebug] Extracted sourceID: \(sourceID), filePath: \(filePath)", category: .player)

        // 2. Look up the MediaSource
        guard let source = mediaSourcesManager?.source(byID: sourceID) else {
            LoggingService.shared.error("[SubtitleDebug] Media source not found for ID: \(sourceID)", category: .player)
            throw MediaSourceError.unknown("Media source not found")
        }

        LoggingService.shared.debug("[SubtitleDebug] Found source: \(source.name), type: \(source.type)", category: .player)

        let password = mediaSourcesManager?.password(for: source)
        let parentPath = (filePath as NSString).deletingLastPathComponent
        let fileName = (filePath as NSString).lastPathComponent

        LoggingService.shared.debug("[SubtitleDebug] parentPath: \(parentPath), fileName: \(fileName)", category: .player)

        // 3. Fetch folder contents based on source type (with cache for queued playback)
        let cacheKey = "\(sourceID):\(parentPath)"
        let folderFiles: [MediaFile]

        if let cached = folderFilesCache[cacheKey] {
            LoggingService.shared.debug("[SubtitleDebug] Using cached folder listing for \(cacheKey) (\(cached.count) files)", category: .player)
            folderFiles = cached
        } else {
            switch source.type {
            case .webdav:
                guard let webDAVClient else {
                    throw MediaSourceError.unknown("WebDAV client not available")
                }
                folderFiles = try await webDAVClient.listFiles(at: parentPath, source: source, password: password)

            case .smb:
                guard let smbClient else {
                    throw MediaSourceError.unknown("SMB client not available")
                }
                folderFiles = try await smbClient.listFiles(at: parentPath, source: source, password: password)

            case .localFolder:
                guard let localFileClient else {
                    throw MediaSourceError.unknown("Local file client not available")
                }
                folderFiles = try await localFileClient.listFiles(at: parentPath, source: source)
            }
            folderFilesCache[cacheKey] = folderFiles
            LoggingService.shared.debug("[SubtitleDebug] Listed \(folderFiles.count) files in folder, cached as \(cacheKey)", category: .player)
        }

        // 4. Find the MediaFile for this video
        guard let mediaFile = folderFiles.first(where: { $0.name == fileName }) else {
            throw MediaSourceError.pathNotFound("Video file not found in folder")
        }

        // 5. Find matching subtitles
        let subtitleCaptions = mediaFile.findMatchingSubtitles(in: folderFiles)

        // 6. Build stream and process captions based on source type
        switch source.type {
        case .webdav:
            // Get auth headers for WebDAV
            var authHeaders: [String: String]?
            if let webDAVClient {
                authHeaders = await webDAVClient.authHeaders(for: source, password: password)
            }
            let stream = mediaFile.toStream(authHeaders: authHeaders)
            // Subtitles can use remote URLs directly for WebDAV
            return (stream, subtitleCaptions)

        case .smb:
            guard let smbClient else {
                throw MediaSourceError.unknown("SMB client not available")
            }

            let folderKey = "\(sourceID):\(parentPath)"

            // Pre-download ALL subtitles in folder on first access.
            // Must complete before MPV opens any SMB connection.
            // For queued videos from the same folder, subtitles will already be cached.
            if !preDownloadedSubtitleFolders.contains(folderKey) {
                let allSubtitleFiles = folderFiles.filter { $0.isSubtitle }
                LoggingService.shared.logMediaSources("Pre-downloading \(allSubtitleFiles.count) subtitle(s) from folder: \(parentPath)")

                for subtitleFile in allSubtitleFiles {
                    do {
                        let localURL = try await smbClient.downloadSubtitleToTemp(
                            file: subtitleFile,
                            source: source,
                            password: password,
                            videoID: folderKey
                        )
                        downloadedSubtitlesCache[subtitleFile.id] = localURL
                        LoggingService.shared.logMediaSources("Pre-downloaded subtitle: \(subtitleFile.name) → \(localURL.lastPathComponent)")
                    } catch {
                        LoggingService.shared.error(
                            "Failed to pre-download subtitle \(subtitleFile.name): \(error.localizedDescription)",
                            category: .general
                        )
                    }
                }

                preDownloadedSubtitleFolders.insert(folderKey)

                // Release app SMB context before MPV opens its connection.
                // libsmbclient uses process-global talloc state that corrupts
                // when two contexts access the same server concurrently.
                await smbClient.clearCache(for: source)
                LoggingService.shared.logMediaSources("Cleared SMB context cache before playback")
            }

            // Construct video playback URL (pure string manipulation, no libsmbclient)
            let playbackURL = try await smbClient.constructPlaybackURL(
                for: mediaFile,
                source: source,
                password: password
            )
            let stream = Stream(url: playbackURL, resolution: nil, format: mediaFile.fileExtension)

            // Build captions from pre-downloaded local files
            var localCaptions: [Caption] = []
            for subtitle in subtitleCaptions {
                if let subtitleFile = folderFiles.first(where: { $0.url == subtitle.url }),
                   let localURL = downloadedSubtitlesCache[subtitleFile.id] {
                    localCaptions.append(Caption(
                        label: subtitle.label,
                        languageCode: subtitle.languageCode,
                        url: localURL
                    ))
                    LoggingService.shared.info(
                        "Using pre-downloaded subtitle: \(subtitleFile.name)",
                        category: .general
                    )
                }
            }

            return (stream, localCaptions)

        case .localFolder:
            // Local folder - no auth needed, use file:// URLs directly
            let stream = mediaFile.toStream(authHeaders: nil)
            return (stream, subtitleCaptions)
        }
    }

    // MARK: - Private Methods

    /// Checks if the stream URL goes through Yattee Server's fast download endpoint.
    /// Fast endpoint streams don't have Content-Length, so MPV can't determine accurate duration.
    /// In this case, we should use the API-provided duration instead.
    private func isFastEndpointStream(_ stream: Stream?) -> Bool {
        guard let urlString = stream?.url.absoluteString else { return false }
        return urlString.contains("/proxy/fast/")
    }

    /// Locks duration from API if playing through fast endpoint.
    /// This prevents progress bar jitter when MPV reports changing duration during progressive download.
    private func lockDurationIfNeeded(for video: Video, stream: Stream?) {
        if isFastEndpointStream(stream), video.duration > 0 {
            state.lockDuration(video.duration)
            LoggingService.shared.debug("Locked duration from API: \(video.duration)s (fast endpoint stream)", category: .player)
        }
    }

    private func setupAudioSession() {
        #if os(iOS) || os(tvOS)
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .moviePlayback)
            try session.setActive(true)

            // Only register observer once
            guard !hasRegisteredInterruptionObserver else { return }
            hasRegisteredInterruptionObserver = true

            LoggingService.shared.debug("Registering audio session interruption observer", category: .player)

            // Register for audio interruption notifications (phone calls, alarms, etc.)
            NotificationCenter.default.addObserver(
                forName: AVAudioSession.interruptionNotification,
                object: session,
                queue: .main
            ) { [weak self] notification in
                // Extract values before async boundary to satisfy Sendable requirements
                guard let userInfo = notification.userInfo,
                      let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
                      let type = AVAudioSession.InterruptionType(rawValue: typeValue) else {
                    return
                }
                let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt

                Task { @MainActor [weak self] in
                    LoggingService.shared.debug("Audio interruption notification received, type: \(type.rawValue), options: \(optionsValue ?? 0)", category: .player)
                    self?.handleAudioSessionInterruption(type: type, optionsValue: optionsValue)
                }
            }
        } catch {
            LoggingService.shared.logPlayerError("Audio session setup failed", error: error)
        }
        #endif
    }

    #if os(iOS) || os(tvOS)
    private func handleAudioSessionInterruption(type: AVAudioSession.InterruptionType, optionsValue: UInt?) {
        LoggingService.shared.debug("handleAudioSessionInterruption called, current playbackState: \(state.playbackState), wasInterrupted: \(wasInterrupted)", category: .player)

        switch type {
        case .began:
            LoggingService.shared.debug("Audio session interrupted (began), playbackState: \(state.playbackState)", category: .player)
            // Audio was interrupted (phone call, alarm, etc.)
            if state.playbackState == .playing {
                LoggingService.shared.debug("Pausing playback due to interruption", category: .player)
                // Call full pause() to properly pause the backend
                pause()
                wasInterrupted = true
            } else {
                LoggingService.shared.debug("Not pausing - playbackState is not .playing", category: .player)
            }
        case .ended:
            LoggingService.shared.debug("Audio session interruption ended, wasInterrupted: \(wasInterrupted)", category: .player)
            // Interruption ended - check if we should resume
            if let optionsValue {
                let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
                LoggingService.shared.debug("Interruption options: shouldResume=\(options.contains(.shouldResume))", category: .player)
                if options.contains(.shouldResume) && wasInterrupted {
                    LoggingService.shared.debug("Auto-resuming playback after interruption", category: .player)
                    // Reactivate audio session before resuming - iOS requires this after interruption
                    do {
                        try AVAudioSession.sharedInstance().setActive(true)
                        LoggingService.shared.debug("Audio session reactivated successfully", category: .player)
                    } catch {
                        LoggingService.shared.error("Failed to reactivate audio session: \(error.localizedDescription)", category: .player)
                    }
                    resume()
                } else {
                    LoggingService.shared.debug("Not auto-resuming: shouldResume=\(options.contains(.shouldResume)), wasInterrupted=\(wasInterrupted)", category: .player)
                }
            } else {
                LoggingService.shared.debug("No interruption options provided", category: .player)
            }
            wasInterrupted = false
        @unknown default:
            LoggingService.shared.debug("Unknown interruption type: \(type.rawValue)", category: .player)
            break
        }
    }
    #endif

    private func fetchVideoStreamsAndCaptions(for video: Video) async throws -> (Video, [Stream], [Caption]) {
        let result = try await fetchVideoStreamsAndCaptionsAndStoryboards(for: video)
        return (result.0, result.1, result.2)
    }

    private func fetchVideoStreamsAndCaptionsAndStoryboards(for video: Video) async throws -> (Video, [Stream], [Caption], [Storyboard]) {
        // Handle media source videos (WebDAV, SMB, and local folders)
        // These don't need API calls - we reconstruct the stream from the stored URL
        if case .extracted(let extractor, let originalURL) = video.id.source {
            if extractor == MediaFile.webdavProvider
                || extractor == MediaFile.localFolderProvider
                || extractor == MediaFile.smbProvider {
                let stream = try await createStreamForMediaSource(video: video, url: originalURL, extractor: extractor)
                return (video, [stream], [], [])
            }
        }

        guard let instance = try await findInstance(for: video) else {
            throw APIError.noInstance
        }

        // For extracted videos, use the extract endpoint with the original URL
        // (stream URLs expire, so we need to re-extract each time)
        if case .extracted(_, let originalURL) = video.id.source {
            guard instance.type == .yatteeServer else {
                throw APIError.notSupported
            }
            let result = try await contentService.extractURL(originalURL, instance: instance)
            return (result.video, result.streams, result.captions, [])
        }

        // Fetch full video details, streams, captions, and storyboards in a single API call
        // (for Invidious, this is a single request; for other backends, calls are made in parallel)
        let result = try await contentService.videoWithStreamsAndCaptionsAndStoryboards(id: video.id.videoID, instance: instance)
        return (result.video, result.streams, result.captions, result.storyboards)
    }

    /// Creates a stream for media source videos (WebDAV, SMB, or local folder).
    /// For WebDAV, adds authentication headers. For SMB, constructs URL with embedded credentials.
    private func createStreamForMediaSource(video: Video, url: URL, extractor: String) async throws -> Stream {
        // Parse the MediaSource UUID from the video ID
        // Format: "UUID:/path/to/file.mp4"
        let videoID = video.id.videoID
        var headers: [String: String]? = nil
        var playbackURL = url

        if let separatorIndex = videoID.firstIndex(of: ":"),
           let sourceUUID = UUID(uuidString: String(videoID[..<separatorIndex])) {
            // For WebDAV sources, add authentication headers
            if extractor == MediaFile.webdavProvider {
                if let source = mediaSourcesManager?.sources.first(where: { $0.id == sourceUUID }) {
                    if let username = source.username,
                       let password = mediaSourcesManager?.password(for: source) {
                        let credentials = "\(username):\(password)"
                        if let credentialsData = credentials.data(using: .utf8) {
                            let base64Credentials = credentialsData.base64EncodedString()
                            headers = ["Authorization": "Basic \(base64Credentials)"]
                            LoggingService.shared.logPlayer("Media source: Created WebDAV stream with auth for '\(source.name)'")
                        }
                    } else {
                        LoggingService.shared.logPlayer("Media source: Created WebDAV stream without auth (no credentials) for '\(source.name)'")
                    }
                } else {
                    LoggingService.shared.logPlayer("Media source: WebDAV source not found for UUID \(sourceUUID)")
                }
            }
            // For SMB sources, construct URL with embedded credentials
            else if extractor == MediaFile.smbProvider {
                if let source = mediaSourcesManager?.sources.first(where: { $0.id == sourceUUID }) {
                    // Reconstruct MediaFile from video to use SMBClient
                    let path = String(videoID.dropFirst(sourceUUID.uuidString.count + 1))
                    let mediaFile = MediaFile(
                        source: source,
                        path: path,
                        name: url.lastPathComponent,
                        isDirectory: false
                    )

                    let password = mediaSourcesManager?.password(for: source)
                    if let smbClient {
                        playbackURL = try await smbClient.constructPlaybackURL(
                            for: mediaFile,
                            source: source,
                            password: password
                        )
                    } else {
                        LoggingService.shared.logPlayer("Media source: SMBClient not available, using original URL")
                    }
                    LoggingService.shared.logPlayer("Media source: Created SMB stream with embedded auth for '\(source.name)' - URL: \(playbackURL.sanitized)")
                } else {
                    LoggingService.shared.logPlayer("Media source: SMB source not found for UUID \(sourceUUID)")
                }
            }
            // Local folder
            else {
                LoggingService.shared.logPlayer("Media source: Created local folder stream")
            }
        } else {
            LoggingService.shared.logPlayer("Media source: Could not parse UUID from videoID \(videoID)")
        }

        // Create stream with placeholder resolution and audio codec so it's recognized as muxed
        // (actual values are unknown until playback, but MPV handles all formats)
        return Stream(
            url: playbackURL,
            resolution: .p720,  // Placeholder - actual resolution unknown
            format: url.pathExtension,
            videoCodec: "avc1",  // Placeholder to indicate video content
            audioCodec: "aac",   // Placeholder to mark as muxed (has audio)
            httpHeaders: headers
        )
    }

    private func selectStreamAndBackend(from streams: [Stream]) -> (stream: Stream?, audioStream: Stream?, backend: PlayerBackendType) {
        // Try preferred backend first
        if let (stream, audioStream) = selectStreams(for: preferredBackendType, from: streams) {
            return (stream, audioStream, preferredBackendType)
        }

        // Fallback to any available backend
        for backendType in backendFactory.availableBackends {
            if let (stream, audioStream) = selectStreams(for: backendType, from: streams) {
                return (stream, audioStream, backendType)
            }
        }

        return (nil, nil, preferredBackendType)
    }

    /// Selects best streams for preloading (exposed for QueueManager).
    func selectStreamsForPreload(from streams: [Stream]) -> (stream: Stream?, audioStream: Stream?) {
        let result = selectStreamAndBackend(from: streams)
        return (result.stream, result.audioStream)
    }

    private func selectStreams(for backendType: PlayerBackendType, from streams: [Stream]) -> (video: Stream, audio: Stream?)? {
        let supportedFormats = backendType.supportedFormats
        let dashEnabled = settingsManager?.dashEnabled ?? false

        // Get user's original quality preference (before network adjustments)
        let userPreferredQuality = settingsManager?.preferredQuality ?? .auto

        // Network-aware quality selection for fixed-bitrate streams
        let effectiveQuality: VideoQuality
        if let monitor = connectivityMonitor {
            if monitor.isConstrained {
                // Low Data Mode - be very conservative
                effectiveQuality = .sd480p
            } else if monitor.isCellular || monitor.isExpensive {
                // Cellular/expensive - use cellular quality setting
                effectiveQuality = settingsManager?.cellularQuality ?? .hd720p
            } else {
                effectiveQuality = userPreferredQuality
            }
        } else {
            effectiveQuality = userPreferredQuality
        }

        // Separate streams by type
        let videoOnlyStreams = streams.filter { stream in
            guard !stream.isAudioOnly && stream.isVideoOnly else { return false }
            let format = StreamFormat.detect(from: stream)
            return supportedFormats.contains(format)
        }

        let muxedStreams = streams.filter { stream in
            let format = StreamFormat.detect(from: stream)
            guard supportedFormats.contains(format) else { return false }
            if format == .dash && !dashEnabled { return false }
            // Only include HLS/DASH if they have video (audio-only HLS/DASH should be treated as audio streams)
            if format == .hls || format == .dash {
                return !stream.isAudioOnly
            }
            return stream.isMuxed
        }

        let audioStreams = streams.filter { $0.isAudioOnly }

        // Check for audio-only content (no real video streams available)
        // This handles cases like SoundCloud where HLS is audio-only but not marked as such
        let hasRealVideoStreams = !videoOnlyStreams.isEmpty || muxedStreams.contains { stream in
            // Real video muxed streams have resolution info
            // HLS/DASH without resolution could be audio-only (can't tell without parsing)
            let format = StreamFormat.detect(from: stream)
            if format == .hls || format == .dash {
                return stream.resolution != nil
            }
            return true
        }

        if !hasRealVideoStreams && !audioStreams.isEmpty {
            LoggingService.shared.debug("Stream selection: Audio-only content detected, using best audio stream", category: .player)
            // Select best audio stream by bitrate
            let bestAudio = audioStreams.sorted { ($0.bitrate ?? 0) > ($1.bitrate ?? 0) }.first!
            return (bestAudio, nil)
        }

        // Get the maximum resolution based on effective quality preference
        let maxResolution = effectiveQuality.maxResolution

        // For live streams, always prefer HLS/DASH (designed for live streaming)
        // Live streams with direct MP4 URLs (live=1&hang=1) don't work reliably
        let isLiveStream = streams.contains(where: { $0.isLive })
        if isLiveStream {
            if let hlsStream = muxedStreams.first(where: { StreamFormat.detect(from: $0) == .hls }) {
                LoggingService.shared.debug("Stream selection: Using HLS for live stream", category: .player)
                return (hlsStream, nil)
            }
            if dashEnabled, let dashStream = muxedStreams.first(where: { StreamFormat.detect(from: $0) == .dash }) {
                LoggingService.shared.debug("Stream selection: Using DASH for live stream", category: .player)
                return (dashStream, nil)
            }
            LoggingService.shared.warning("Stream selection: No HLS/DASH available for live stream, falling back to adaptive formats", category: .player)
        }

        // Note: For non-live videos, we prefer progressive formats (MP4/WebM) over HLS/DASH
        // because they typically offer better quality. HLS/DASH are only used as last resort.
        // Live streams are already handled above with HLS/DASH preference.

        // Try to find the best video-only stream + audio (for MPV which supports all formats)
        if backendType == .mpv && !videoOnlyStreams.isEmpty && !audioStreams.isEmpty {
            let filteredVideoStreams: [Stream]
            if let maxRes = maxResolution {
                filteredVideoStreams = videoOnlyStreams.filter { stream in
                    guard let resolution = stream.resolution else { return true }
                    return resolution <= maxRes
                }
            } else {
                filteredVideoStreams = videoOnlyStreams
            }

            // Filter out codecs with priority 0 (software decode) if hardware options exist
            let hardwareDecodableStreams = filteredVideoStreams.filter { videoCodecPriority($0.videoCodec) > 0 }
            let streamsToConsider = hardwareDecodableStreams.isEmpty ? filteredVideoStreams : hardwareDecodableStreams

            // Sort by resolution first, then by codec priority
            let sortedVideo = streamsToConsider.sorted { s1, s2 in
                let res1 = s1.resolution ?? .p360
                let res2 = s2.resolution ?? .p360
                if res1 != res2 {
                    return res1 > res2
                }
                // Same resolution - prefer better codec
                return videoCodecPriority(s1.videoCodec) > videoCodecPriority(s2.videoCodec)
            }

            if let bestVideo = sortedVideo.first {
                // Select best audio stream based on preferred language, codec, and bitrate
                let preferredAudioLanguage = settingsManager?.preferredAudioLanguage
                let bestAudio = audioStreams
                    .sorted { stream1, stream2 in
                        // First priority: preferred language or original audio
                        if let preferred = preferredAudioLanguage {
                            // User selected a specific language
                            let lang1 = stream1.audioLanguage ?? ""
                            let lang2 = stream2.audioLanguage ?? ""
                            let matches1 = lang1.hasPrefix(preferred)
                            let matches2 = lang2.hasPrefix(preferred)
                            if matches1 != matches2 { return matches1 }
                        } else {
                            // No preference set - prefer original audio track
                            if stream1.isOriginalAudio != stream2.isOriginalAudio {
                                return stream1.isOriginalAudio
                            }
                        }

                        // Second priority: prefer Opus > AAC for MPV (better quality/compression)
                        let codecPriority1 = audioCodecPriority(stream1.audioCodec)
                        let codecPriority2 = audioCodecPriority(stream2.audioCodec)
                        if codecPriority1 != codecPriority2 {
                            return codecPriority1 > codecPriority2
                        }

                        // Third priority: higher bitrate
                        return (stream1.bitrate ?? 0) > (stream2.bitrate ?? 0)
                    }
                    .first

                if let audio = bestAudio {
                    return (bestVideo, audio)
                }
            }
        }

        // Fallback to muxed streams - prefer progressive formats over HLS/DASH for non-live content
        let filteredMuxed: [Stream]
        if let maxRes = maxResolution {
            filteredMuxed = muxedStreams.filter { stream in
                guard let resolution = stream.resolution else { return true }
                return resolution <= maxRes
            }
        } else {
            filteredMuxed = muxedStreams
        }

        // Sort: prefer non-HLS/DASH (progressive) formats, then by resolution
        let sortedMuxed = filteredMuxed.sorted { s1, s2 in
            let format1 = StreamFormat.detect(from: s1)
            let format2 = StreamFormat.detect(from: s2)
            let isAdaptive1 = format1 == .hls || format1 == .dash
            let isAdaptive2 = format2 == .hls || format2 == .dash

            // Prefer progressive formats for non-live content
            if isAdaptive1 != isAdaptive2 {
                return !isAdaptive1 // non-adaptive (false) comes first
            }
            return (s1.resolution ?? .p360) > (s2.resolution ?? .p360)
        }

        if let bestMuxed = sortedMuxed.first {
            return (bestMuxed, nil)
        }

        // Last resort: any muxed stream (HLS/DASH will be selected here if nothing else available)
        if let anyMuxed = muxedStreams.sorted(by: { ($0.resolution ?? .p360) > ($1.resolution ?? .p360) }).first {
            return (anyMuxed, nil)
        }

        return nil
    }

    /// Returns codec priority for video streams (higher = better).
    /// Prefers hardware-decodable codecs for battery efficiency.
    private func videoCodecPriority(_ codec: String?) -> Int {
        HardwareCapabilities.shared.codecPriority(for: codec)
    }

    /// Returns codec priority for audio streams.
    /// Opus and AAC are treated equally - let bitrate decide quality.
    private func audioCodecPriority(_ codec: String?) -> Int {
        guard let codec = codec?.lowercased() else { return 0 }
        if codec.contains("opus") || codec.contains("aac") || codec.contains("mp4a") {
            return 1 // Both are good - bitrate will decide
        }
        return 0
    }

    private func ensureBackend(type: PlayerBackendType) async throws -> any PlayerBackend {
        // Reuse existing backend if same type
        if let current = currentBackend, current.backendType == type {
            return current
        }

        // Create new backend
        let backend = try backendFactory.createBackend(type: type)
        backend.delegate = self
        currentBackend = backend

        // Configure MPV-specific settings
        #if os(iOS) || os(macOS)
        if let mpvBackend = backend as? MPVBackend {
            // Configure PiP callbacks
            if let coordinator = navigationCoordinator {
                mpvBackend.onRestoreFromPiP = { [weak coordinator] in
                    // If mini player video is disabled, expand player for restore
                    // Otherwise video continues in mini player
                    if MiniPlayerSettings.cached.showVideo == false {
                        coordinator?.expandPlayer()
                    }
                }
                mpvBackend.onPiPDidStart = { [weak coordinator] in
                    guard let coordinator else {
                        LoggingService.shared.debug("PlayerService: onPiPDidStart - coordinator is nil", category: .player)
                        return
                    }
                    // Collapse the player sheet/window when PiP starts
                    LoggingService.shared.debug("PlayerService: onPiPDidStart - isPlayerExpanded=\(coordinator.isPlayerExpanded)", category: .player)
                    if coordinator.isPlayerExpanded {
                        // Set collapsing first so mini player shows video immediately
                        coordinator.isPlayerCollapsing = true
                        coordinator.isPlayerExpanded = false
                        LoggingService.shared.debug("PlayerService: onPiPDidStart - set isPlayerExpanded to false", category: .player)
                    }
                }
                #if os(macOS)
                // Clean up hidden window when PiP is closed via X button (not restore)
                mpvBackend.onPiPDidStopWithoutRestore = {
                    LoggingService.shared.debug("PlayerService: onPiPDidStopWithoutRestore - cleaning up hidden window", category: .player)
                    ExpandedPlayerWindowManager.shared.cleanupAfterPiP()
                }
                #endif
            }
        }
        #endif

        return backend
    }

    private var instancesManager: InstancesManager?
    private weak var mediaSourcesManager: MediaSourcesManager?
    private var smbClient: SMBClient?
    private var webDAVClient: WebDAVClient?
    private var localFileClient: LocalFileClient?
    private var folderFilesCache: [String: [MediaFile]] = [:]

    /// Cache of pre-downloaded subtitle local file URLs.
    /// Key: subtitle MediaFile.id, Value: local temp URL
    private var downloadedSubtitlesCache: [String: URL] = [:]

    /// Tracks folders whose subtitles have been pre-downloaded.
    /// Prevents re-downloading when resolving queued videos from the same folder.
    private var preDownloadedSubtitleFolders: Set<String> = []

    /// Sets the instances manager for finding instances.
    func setInstancesManager(_ manager: InstancesManager) {
        self.instancesManager = manager
    }

    /// Sets the media sources manager for WebDAV/SMB/local folder playback.
    func setMediaSourcesManager(_ manager: MediaSourcesManager) {
        self.mediaSourcesManager = manager
    }

    /// Sets the SMB client for SMB playback.
    func setSMBClient(_ client: SMBClient) {
        self.smbClient = client
    }

    /// Sets the WebDAV client for WebDAV playback.
    func setWebDAVClient(_ client: WebDAVClient) {
        self.webDAVClient = client
    }

    /// Sets the local file client for local folder playback.
    func setLocalFileClient(_ client: LocalFileClient) {
        self.localFileClient = client
    }

    /// Sets the settings manager for accessing user preferences.
    func setSettingsManager(_ manager: SettingsManager) {
        self.settingsManager = manager
        self.backendSwitcher.settingsManager = manager
        self.nowPlayingService.settingsManager = manager
        // Reconfigure remote commands now that we have settings
        nowPlayingService.configureRemoteCommands()
        // Note: preferredBackendType is now computed directly from settingsManager
    }

    /// Reconfigures system control buttons (Control Center, Lock Screen) based on current settings.
    /// Call this when system controls settings change.
    func reconfigureSystemControls(
        mode: SystemControlsMode? = nil,
        duration: SystemControlsSeekDuration? = nil
    ) {
        nowPlayingService.configureRemoteCommands(mode: mode, duration: duration)
    }

    /// Observer for preset changes to reconfigure system controls.
    private var presetChangeObserver: NSObjectProtocol?

    /// Sets the player controls layout service for reading preset-specific settings.
    func setPlayerControlsLayoutService(_ service: PlayerControlsLayoutService) {
        self.playerControlsLayoutService = service
        nowPlayingService.playerControlsLayoutService = service

        // Reconfigure with the actual saved settings now that layout service is available
        nowPlayingService.configureRemoteCommands()

        // Observe preset changes to reconfigure system controls
        presetChangeObserver = NotificationCenter.default.addObserver(
            forName: .playerControlsActivePresetDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor [weak self] in
                self?.reconfigureSystemControls()
            }
        }
    }

    /// Sets the download manager for checking downloaded videos.
    func setDownloadManager(_ manager: DownloadManager) {
        self.downloadManager = manager
    }

    /// Sets the DeArrow branding provider for enhanced titles.
    func setDeArrowBrandingProvider(_ provider: DeArrowBrandingProvider) {
        nowPlayingService.deArrowBrandingProvider = provider
    }

    /// Sets the connectivity monitor for network-aware quality selection.
    func setConnectivityMonitor(_ monitor: ConnectivityMonitor) {
        self.connectivityMonitor = monitor
    }

    /// Sets the toast manager for displaying notifications.
    func setToastManager(_ manager: ToastManager) {
        self.toastManager = manager
    }

    /// Sets the queue manager for queue operations.
    func setQueueManager(_ manager: QueueManager) {
        self.queueManager = manager
    }

    /// Sets the navigation coordinator for waiting on sheet animations.
    func setNavigationCoordinator(_ coordinator: NavigationCoordinator) {
        self.navigationCoordinator = coordinator

        #if os(iOS)
        // Configure PiP restore callback - don't expand player, just let PiP close
        // Video continues in mini player; user taps mini player to expand
        if let mpvBackend = currentBackend as? MPVBackend {
            mpvBackend.onRestoreFromPiP = { [weak coordinator] in
                // If mini player video is disabled, expand player for restore
                // Otherwise video continues in mini player
                if MiniPlayerSettings.cached.showVideo == false {
                    coordinator?.expandPlayer()
                }
            }
        }
        #endif
    }

    /// Sets the handoff manager for activity updates.
    func setHandoffManager(_ manager: HandoffManager) {
        self.handoffManager = manager
    }

    #if os(iOS)
    /// Called when the player sheet appears.
    func playerSheetDidAppear() {
        let backendType = currentBackend?.backendType.rawValue ?? "none"
        let playbackState = state.playbackState
        LoggingService.shared.debug("PlayerService: playerSheetDidAppear - backend=\(backendType), playbackState=\(playbackState)", category: .player)

        // Re-enable visual tracks and reattach layer when sheet appears
        let backgroundEnabled = settingsManager?.backgroundPlaybackEnabled ?? true
        let isPiPActive = (currentBackend as? MPVBackend)?.isPiPActive ?? false
        LoggingService.shared.debug("PlayerService: sheetDidAppear checks - backgroundEnabled=\(backgroundEnabled), isPiPActive=\(isPiPActive)", category: .player)

        guard backgroundEnabled && !isPiPActive else {
            LoggingService.shared.debug("PlayerService: skipping visibility handling (backgroundEnabled=\(backgroundEnabled), isPiPActive=\(isPiPActive))", category: .player)
            return
        }

        if let mpvBackend = currentBackend as? MPVBackend {
            LoggingService.shared.debug("Player sheet appeared - re-enabling video (MPV)", category: .player)
            mpvBackend.handlePlayerSheetVisibility(isVisible: true)
        }
    }

    /// Called when the player sheet disappears.
    func playerSheetDidDisappear() {
        let backendType = currentBackend?.backendType.rawValue ?? "none"
        let playbackState = state.playbackState
        LoggingService.shared.debug("PlayerService: playerSheetDidDisappear - backend=\(backendType), playbackState=\(playbackState)", category: .player)

        // Disable visual tracks and detach layer for background audio playback
        let backgroundEnabled = settingsManager?.backgroundPlaybackEnabled ?? true
        let mpvPiPActive = (currentBackend as? MPVBackend)?.isPiPActive ?? false
        LoggingService.shared.debug("PlayerService: sheetDidDisappear checks - backgroundEnabled=\(backgroundEnabled), mpvPiPActive=\(mpvPiPActive)", category: .player)

        guard backgroundEnabled && !mpvPiPActive else {
            LoggingService.shared.debug("PlayerService: skipping visibility handling on disappear (backgroundEnabled=\(backgroundEnabled), mpvPiP=\(mpvPiPActive))", category: .player)
            return
        }

        // Check if mini player video should be visible
        // If so, don't pause rendering - mini player will manage rendering state
        let miniPlayerVideoEnabled = MiniPlayerSettings.cached.showVideo
        let isAudioOnly = state.currentStream?.isAudioOnly == true
        let shouldMiniPlayerShowVideo = miniPlayerVideoEnabled && !isAudioOnly

        if shouldMiniPlayerShowVideo {
            LoggingService.shared.debug("PlayerService: skipping pause - mini player will show video (miniPlayerVideoEnabled=\(miniPlayerVideoEnabled), isAudioOnly=\(isAudioOnly))", category: .player)
            return
        }

        if let mpvBackend = currentBackend as? MPVBackend {
            LoggingService.shared.debug("Player sheet dismissed - disabling video for background playback (MPV)", category: .player)
            mpvBackend.handlePlayerSheetVisibility(isVisible: false)
        }
    }
    #endif

    private func findInstance(for video: Video) async throws -> Instance? {
        guard let instancesManager else { return nil }
        return instancesManager.instance(for: video)
    }

    private func fetchSponsorBlockSegments(for videoID: String) async {
        // Update SponsorBlock API URL from settings
        if let urlString = settingsManager?.sponsorBlockAPIURL,
           let url = URL(string: urlString) {
            await sponsorBlockAPI.setBaseURL(url)
        }

        do {
            let segments = try await sponsorBlockAPI.segments(for: videoID)
            state.sponsorSegments = segments
        } catch {
            LoggingService.shared.logPlayerError("SponsorBlock fetch failed", error: error)
        }
    }

    private func fetchReturnYouTubeDislikeCounts(for videoID: String) async {
        guard settingsManager?.returnYouTubeDislikeEnabled == true else { return }

        do {
            let votes = try await returnYouTubeDislikeAPI.votes(for: videoID)
            state.dislikeCount = votes.dislikes
            // Notify observers that video details updated
            NotificationCenter.default.post(name: .videoDetailsDidLoad, object: nil)
        } catch {
            LoggingService.shared.logPlayerError("Return YouTube Dislike fetch failed", error: error)
        }
    }

    /// Fetches full video details from API and updates state.
    /// Used for downloaded videos that may not have full metadata stored.
    private func fetchAndUpdateVideoDetails(for video: Video) async {
        guard let instance = try? await findInstance(for: video) else { return }

        do {
            let fullVideo = try await contentService.video(id: video.id.videoID, instance: instance)

            // Only update if this is still the current video
            guard state.currentVideo?.id == video.id else { return }

            // Update state with full video (preserving current stream)
            state.setCurrentVideo(fullVideo, stream: state.currentStream, audioStream: state.currentAudioStream)
            NotificationCenter.default.post(name: .videoDetailsDidLoad, object: nil)

            // Also fetch dislike count if enabled
            if case .global = video.id.source {
                await fetchReturnYouTubeDislikeCounts(for: video.id.videoID)
            }
        } catch {
            // Silently fail - offline playback continues with stored metadata
        }
    }

    private func startProgressSaveTimer() {
        progressSaveTimer?.invalidate()
        progressSaveTimer = Timer.scheduledTimer(withTimeInterval: progressSaveInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.saveProgress()
            }
        }
    }

    private func saveProgress() {
        guard settingsManager?.incognitoModeEnabled != true,
              settingsManager?.saveWatchHistory != false else { return }

        guard let video = state.currentVideo,
              state.currentTime > 0 else { return }

        // Save locally only during playback - no iCloud sync overhead
        dataManager.updateWatchProgressLocal(for: video, seconds: state.currentTime, duration: state.duration)

        // Update Handoff activity with current playback time
        handoffManager?.updatePlaybackTime(state.currentTime)
    }

    /// Saves progress as 100% completed when video finishes naturally.
    /// This ensures the watch history shows full completion instead of ~99%.
    private func saveProgressAsCompleted() {
        guard settingsManager?.incognitoModeEnabled != true,
              settingsManager?.saveWatchHistory != false,
              let video = state.currentVideo else { return }

        // Use video.duration (API-reported) to match WatchEntry.duration stored value.
        // This ensures 100% progress since WatchEntry.progress = watchedSeconds / WatchEntry.duration.
        // Fall back to state.duration (MPV-reported) if video.duration is not available.
        let completedDuration = video.duration > 0 ? video.duration : state.duration
        guard completedDuration > 0 else { return }

        // Save the full duration as watched time when video completes
        dataManager.updateWatchProgressLocal(for: video, seconds: completedDuration, duration: completedDuration)

        // Update Handoff activity with completed time
        handoffManager?.updatePlaybackTime(completedDuration)
    }

    /// Saves progress and triggers iCloud sync for watch history.
    /// Call this when video playback ends or switches to a different video.
    private func saveProgressAndSync() {
        guard settingsManager?.incognitoModeEnabled != true,
              settingsManager?.saveWatchHistory != false else { return }

        guard let video = state.currentVideo,
              state.currentTime > 0 else { return }

        // Save and queue for iCloud sync (used when video closes/switches)
        dataManager.updateWatchProgress(for: video, seconds: state.currentTime, duration: state.duration)
        NotificationCenter.default.post(name: .watchHistoryDidChange, object: nil)
    }

    private func checkSponsorBlockSegments(at time: Double) {
        // Read settings - use defaults if settings manager not available
        let enabled = settingsManager?.sponsorBlockEnabled ?? true
        let enabledCategories = settingsManager?.sponsorBlockCategories ?? SponsorBlockCategory.defaultEnabled

        guard enabled else { return }

        // Find segment at current time that matches enabled categories
        let applicableSegments = state.sponsorSegments.skippable().inCategories(enabledCategories)
        if let segment = applicableSegments.segment(at: time) {
            // Auto-skip all enabled categories
            // Prevent duplicate skips for the same segment
            guard lastSkippedSegmentID != segment.id else { return }

            if delegate?.playerService(self, shouldSkipSegment: segment) ?? true {
                lastSkippedSegmentID = segment.id
                Task {
                    await skipSegment(segment)
                }
            }
        } else {
            state.currentSegment = nil
            // Clear last skipped when not in any segment (allows re-skip if user seeks back)
            lastSkippedSegmentID = nil
        }
    }

    /// Skips a specific segment by seeking past it.
    private func skipSegment(_ segment: SponsorBlockSegment) async {
        let skipTarget = segment.endTime + 0.1

        // Don't skip if target is past video duration - this would cause an infinite loop
        // since we'd seek to end, still be "in" the segment, and skip again
        guard state.duration > 0, skipTarget < state.duration else {
            LoggingService.shared.logPlayer("SponsorBlock: not skipping \(segment.category.rawValue) segment (extends past video end)", details: "\(segment.startTime)s - \(segment.endTime)s, duration: \(state.duration)s")
            return
        }

        LoggingService.shared.logPlayer("SponsorBlock: skipping \(segment.category.rawValue) segment", details: "\(segment.startTime)s - \(segment.endTime)s")
        // Show loading for early skips (intro, early sponsors) to avoid brief video flash
        // But only if we haven't already shown video (still in loading state)
        let isEarlySkip = segment.startTime < 30
        let isStillLoading = state.playbackState == .loading
        await seek(to: skipTarget, showLoading: isEarlySkip && isStillLoading)
    }

    private func cleanup() {
        // Clean up temp subtitle files for current video
        if let currentVideo = state.currentVideo {
            cleanupTempSubtitles(for: currentVideo.id.id)
        }

        progressSaveTimer?.invalidate()
        progressSaveTimer = nil

        // Remove audio session interruption observer
        #if os(iOS) || os(tvOS)
        NotificationCenter.default.removeObserver(self, name: AVAudioSession.interruptionNotification, object: nil)
        hasRegisteredInterruptionObserver = false
        #endif

        // Cancel any ongoing play task
        currentPlayTask?.cancel()
        currentPlayTask = nil

        currentBackend?.stop()
        // Keep backend alive for reuse - prevents race condition where old backend's
        // delayed deinit destroys render context that new backend is using
        // currentBackend = nil
    }

    /// Cleans up temporary subtitle files for a given video.
    /// Call this when closing/stopping a video.
    /// - Parameter videoID: The video ID whose subtitles to clean up.
    private func cleanupTempSubtitles(for videoID: String) {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("yattee-subtitles", isDirectory: true)
            .appendingPathComponent(videoID, isDirectory: true)

        do {
            if FileManager.default.fileExists(atPath: tempDir.path) {
                try FileManager.default.removeItem(at: tempDir)
                LoggingService.shared.debug("Cleaned up temp subtitles for: \(videoID)", category: .player)
            }
        } catch {
            LoggingService.shared.error(
                "Failed to clean up temp subtitles for \(videoID): \(error.localizedDescription)",
                category: .player
            )
        }
    }

    /// Cleans up all temporary subtitle files (pre-downloaded and per-video).
    /// Called when stopping playback entirely.
    private func cleanupAllTempSubtitles() {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("yattee-subtitles", isDirectory: true)

        do {
            if FileManager.default.fileExists(atPath: tempDir.path) {
                try FileManager.default.removeItem(at: tempDir)
                LoggingService.shared.debug("Cleaned up all temp subtitles", category: .player)
            }
        } catch {
            LoggingService.shared.error(
                "Failed to clean up all temp subtitles: \(error.localizedDescription)",
                category: .player
            )
        }
    }

    // MARK: - Chapter Resolution

    /// Resolves chapters for the video using source hierarchy.
    /// Priority: SponsorBlock chapters > description parsing
    /// - Parameter video: The video to resolve chapters for.
    private func resolveChapters(for video: Video) {
        let videoDuration = video.duration > 0 ? video.duration : state.duration
        guard videoDuration > 0 else {
            state.chapters = []
            return
        }

        // 1. Try SponsorBlock chapters (if enabled and segments available)
        let sponsorBlockEnabled = settingsManager?.sponsorBlockEnabled ?? true
        if sponsorBlockEnabled {
            let chapters = state.sponsorSegments.extractChapters(videoDuration: videoDuration)
            if chapters.count >= 2 {
                state.chapters = chapters
                LoggingService.shared.logPlayer("Chapters: \(chapters.count) from SponsorBlock")
                return
            }
        }

        // 2. Fall back to description parsing
        if let description = video.description {
            let introTitle = String(localized: "player.chapters.intro")
            let chapters = ChapterParser.parse(
                description: description,
                videoDuration: videoDuration,
                introTitle: introTitle
            )
            state.chapters = chapters
            if !chapters.isEmpty {
                LoggingService.shared.logPlayer("Chapters: \(chapters.count) from description")
            }
        } else {
            state.chapters = []
        }
    }
}

// MARK: - PlayerBackendDelegate

extension PlayerService: PlayerBackendDelegate {
    func backend(_ backend: any PlayerBackend, didUpdateTime time: TimeInterval) {
        // Ignore time updates while loading a new video - these are stale updates from the previous video
        guard loadingVideoID == nil else { return }

        state.currentTime = time
        delegate?.playerService(self, didUpdateTime: time)
        checkSponsorBlockSegments(at: time)

        // Update Now Playing time periodically (every ~5 seconds to avoid excessive updates)
        let shouldUpdateNowPlaying = Int(time) % 5 == 0
        if shouldUpdateNowPlaying {
            nowPlayingService.updatePlaybackTime(
                currentTime: time,
                duration: state.duration,
                isPlaying: state.playbackState == .playing
            )
        }
    }

    func backend(_ backend: any PlayerBackend, didUpdateDuration duration: TimeInterval) {
        // Skip duration updates when locked from API (fast endpoint streams where
        // file is progressively downloaded and MPV can't determine accurate duration)
        guard !state.isDurationLockedFromAPI else { return }
        state.duration = duration
    }

    func backend(_ backend: any PlayerBackend, didChangeState playbackState: PlaybackState) {
        LoggingService.shared.debug("Backend state changed to: \(playbackState)", category: .player)
        state.setPlaybackState(playbackState)
        delegate?.playerService(self, didChangeState: playbackState)
    }

    func backend(_ backend: any PlayerBackend, didUpdateBufferedTime time: TimeInterval) {
        state.bufferedTime = time
    }

    func backend(_ backend: any PlayerBackend, didUpdateBufferProgress progress: Int) {
        // Only update during initial buffering (before buffer is ready)
        // Skip buffer progress for local files - they load quickly and don't need buffering indicator
        let isLocalFile = state.currentStream?.url.isFileURL == true
        if !state.isBufferReady && !isLocalFile {
            state.bufferProgress = progress
        }
    }

    func backend(_ backend: any PlayerBackend, didEncounterError error: Error) {
        delegate?.playerService(self, didEncounterError: error)
    }

    func backend(_ backend: any PlayerBackend, didUpdateVideoSize width: Int, height: Int) {
        guard width > 0, height > 0 else { return }
        let aspectRatio = Double(width) / Double(height)

        state.videoAspectRatio = aspectRatio
        LoggingService.shared.debug("Video aspect ratio updated: \(aspectRatio) (\(width)x\(height))", category: .player)
    }

    func backend(_ backend: any PlayerBackend, didUpdateRetryState currentRetry: Int, maxRetries: Int, isRetrying: Bool, exhausted: Bool) {
        let retryState = RetryState(
            currentRetry: currentRetry,
            maxRetries: maxRetries,
            isRetrying: isRetrying,
            exhausted: exhausted
        )
        state.setRetryState(retryState)
    }

    func backend(_ backend: any PlayerBackend, didRequestStreamRefresh atTime: TimeInterval?) {
        LoggingService.shared.logPlayer("Stream refresh requested at time: \(atTime ?? -1)")

        Task {
            await refreshStreamsAndResume(atTime: atTime)
        }
    }

    func backendDidBecomeReady(_ backend: any PlayerBackend) {
        // First frame of new video has been rendered - thumbnail can now hide
        state.isFirstFrameReady = true
    }

    func backendDidFinishPlaying(_ backend: any PlayerBackend) {
        // Mark that video ended naturally - prevents play() from saving progress again
        // when switching to next video (100% is already saved below)
        videoEndedNaturally = true

        // Stop the progress save timer BEFORE saving completion
        // Otherwise the timer can overwrite our 100% with a lower value
        progressSaveTimer?.invalidate()
        progressSaveTimer = nil

        state.setPlaybackState(.ended)
        saveProgressAsCompleted()
        delegate?.playerServiceDidFinishPlaying(self)

        // Auto-play immediately if player is not visible (no point showing countdown)
        // UI (ExpandedPlayerSheet) will handle countdown when player is visible
        let autoPlayEnabled = settingsManager?.queueAutoPlayNext ?? true
        let hasNextInQueue = !state.queue.isEmpty

        if autoPlayEnabled && hasNextInQueue {
            let isSheetCollapsed = navigationCoordinator?.isPlayerExpanded != true
            let isInBackground = currentScenePhase == .background
            let isPiPActive = state.pipState == .active

            if isSheetCollapsed || isInBackground || isPiPActive {
                Task {
                    await playNext()
                }
            } else {
                // UI will handle countdown - allow sleep while waiting
                // (preventSleep will be called again when next video starts)
                sleepPreventionService.allowSleep()
            }
        } else {
            // No auto-play will happen - allow sleep
            sleepPreventionService.allowSleep()
        }
    }

    /// Called when a video starts playing to trigger proactive continuation loading.
    func notifyVideoStarted() {
        queueManager?.onVideoStarted()
    }

    /// Handles playback errors by auto-skipping to next video if available and player is not visible.
    /// When player is visible, user can manually tap "Play Next" button on the error overlay.
    private func handlePlaybackErrorAutoSkip() async {
        let autoPlayEnabled = settingsManager?.queueAutoPlayNext ?? true
        let hasNextInQueue = !state.queue.isEmpty

        guard autoPlayEnabled && hasNextInQueue else { return }

        let isSheetCollapsed = navigationCoordinator?.isPlayerExpanded != true
        let isInBackground = currentScenePhase == .background
        let isPiPActive = state.pipState == .active

        // Skip immediately if player is NOT visible to user (no point showing error screen)
        if isSheetCollapsed || isInBackground || isPiPActive {
            // Show toast notification
            toastManager?.showInfo(String(localized: "player.error.skippingToNext.title"))

            await playNext()
        }
    }
}
