//
//  TappableVideoModifier.swift
//  Yattee
//
//  View modifier that makes content tappable to play a video.
//

import SwiftUI

/// View modifier that wraps content in a button that plays a video when tapped.
/// When queue is enabled and a video is playing or queued, shows a sheet with queue options.
/// When nothing is playing or queue is disabled, plays the video directly and queues subsequent videos.
struct TappableVideoModifier: ViewModifier {
    @Environment(\.appEnvironment) private var appEnvironment
    @Environment(\.presentAppSheet) private var presentAppSheet

    let video: Video
    var startTime: Double? = nil
    var customActions: [VideoContextAction] = []
    var context: VideoContextMenuContext = .default
    var includeContextMenu: Bool = true
    var queueSource: QueueSource? = nil
    /// Display label for the queue source (e.g., playlist title, channel name)
    var sourceLabel: String? = nil

    /// All videos in the list (for auto-queuing subsequent videos)
    var videoList: [Video]? = nil
    /// Index of this video in the list
    var videoIndex: Int? = nil

    /// Callback to load more videos via continuation
    nonisolated(unsafe) var loadMoreVideos: LoadMoreVideosCallback? = nil

    // Password alert state (for WebDAV sources)
    @State private var showingPasswordAlert = false
    @State private var sourceNeedingPassword: MediaSource?
    @State private var passwordInput = ""

    /// Whether queue feature is enabled and something is playing or queued,
    /// so "Play Next" / "Add to Queue" are meaningful alternatives to replacing playback.
    private var shouldShowQueueSheet: Bool {
        guard let env = appEnvironment else { return false }
        let queueEnabled = env.settingsManager.queueEnabled
        let state = env.playerService.state
        let hasActivePlayback = state.currentVideo != nil || !state.queue.isEmpty
        return queueEnabled && hasActivePlayback
    }

    func body(content: Content) -> some View {
        Button {
            dismissKeyboard()
            #if os(tvOS)
            let tapAction = appEnvironment?.settingsManager.tvOSVideoTapAction ?? .openInfo
            if tapAction == .openInfo {
                appEnvironment?.navigationCoordinator.navigate(
                    to: .video(.loaded(video), queueContext: queueContext)
                )
            } else {
                checkPasswordAndPlay()
            }
            #else
            checkPasswordAndPlay()
            #endif
        } label: {
            content
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .if(includeContextMenu) { view in
            view.videoContextMenu(
                video: video,
                customActions: customActions,
                context: context,
                startTime: startTime
            )
        }
        .alert(String(localized: "common.authenticationRequired"), isPresented: $showingPasswordAlert) {
            SecureField(String(localized: "common.password"), text: $passwordInput)
            Button(String(localized: "common.cancel"), role: .cancel) {
                passwordInput = ""
                sourceNeedingPassword = nil
            }
            Button(String(localized: "common.connect")) {
                savePasswordAndContinue()
            }
        } message: {
            if let source = sourceNeedingPassword {
                Text(String(localized: "common.enterPassword \(source.name)"))
            }
        }
        .videoQueueContext(queueContext)
    }
    
    /// Creates a VideoQueueContext from the modifier's parameters
    private var queueContext: VideoQueueContext {
        VideoQueueContext(
            video: video,
            queueSource: queueSource,
            sourceLabel: sourceLabel,
            videoList: videoList,
            videoIndex: videoIndex,
            startTime: startTime,
            loadMoreVideos: loadMoreVideos
        )
    }

    // MARK: - Keyboard Handling
    
    /// Dismisses the iOS software keyboard before playing video
    private func dismissKeyboard() {
        #if os(iOS)
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        #endif
    }
    
    // MARK: - Password Check & Playback
    
    /// Checks if video is from WebDAV source needing password, shows alert or plays directly
    private func checkPasswordAndPlay() {
        // Check if video is from WebDAV source needing password
        if let sourceID = video.mediaSourceID,
           let source = appEnvironment?.mediaSourcesManager.source(byID: sourceID),
           appEnvironment?.mediaSourcesManager.needsPassword(for: source) == true {
            sourceNeedingPassword = source
            showingPasswordAlert = true
        } else if shouldShowQueueSheet {
            presentAppSheet(.queueAction(video, queueSource: queueSource))
        } else {
            playVideoAndQueueRest()
        }
    }
    
    /// Saves password for WebDAV source and continues with playback
    private func savePasswordAndContinue() {
        guard let source = sourceNeedingPassword, !passwordInput.isEmpty else { return }
        appEnvironment?.mediaSourcesManager.setPassword(passwordInput, for: source)
        passwordInput = ""
        sourceNeedingPassword = nil
        
        // Now check if we should show queue sheet or play directly
        if shouldShowQueueSheet {
            presentAppSheet(.queueAction(video, queueSource: queueSource))
        } else {
            playVideoAndQueueRest()
        }
    }
    
    /// Plays the tapped video and queues all subsequent videos from the list.
    /// Checks resume action setting for partially watched videos.
    private func playVideoAndQueueRest() {
        guard let env = appEnvironment else { return }

        // Live streams have no fixed timeline, so a resume position is meaningless -
        // never ask, always join at the live edge.
        guard !video.isLive else {
            playVideoWithStartTime(0)
            return
        }

        // Determine the saved progress: prefer explicitly passed startTime, then query database
        // This handles cases where startTime is passed from views like Continue Watching/History
        // that already have the watch position, avoiding issues with data not being synced yet
        let savedProgress: TimeInterval?
        if let passedStartTime = startTime, passedStartTime > 0 {
            // Use the startTime that was passed to the modifier (e.g., from Continue Watching)
            savedProgress = passedStartTime
        } else {
            // Query database for watch progress
            savedProgress = env.dataManager.watchProgress(for: video.id.videoID)
        }

        let videoDuration = video.duration
        // When duration is 0 (not yet loaded), use a large threshold to avoid false "completed" detection
        let completionThreshold = videoDuration > 0 ? videoDuration * 0.9 : Double.greatestFiniteMagnitude
        // Minimum threshold - treat < 5 seconds as "not watched" to avoid asking for very short progress
        let minimumThreshold: TimeInterval = 5

        // Only consider resume logic if there's meaningful saved progress (>5s) and video wasn't completed
        if let savedProgress, savedProgress >= minimumThreshold, savedProgress < completionThreshold {
            let resumeActionSetting = env.settingsManager.resumeAction

            switch resumeActionSetting {
            case .continueWatching:
                // Use saved progress as start time
                playVideoWithStartTime(savedProgress)
            case .startFromBeginning:
                // Always start from beginning
                playVideoWithStartTime(0)
            case .ask:
                // Show the resume action sheet with data bundled together
                presentAppSheet(.resumeAction(
                    video,
                    resumeTime: savedProgress,
                    onContinue: { playVideoWithStartTime(savedProgress) },
                    onStartOver: { playVideoWithStartTime(0) }
                ))
            }
        } else {
            // No saved progress or video was completed - play from beginning
            playVideoWithStartTime(0)
        }
    }

    /// Plays the video with the specified start time.
    private func playVideoWithStartTime(_ time: TimeInterval) {
        guard let env = appEnvironment else { return }

        // If we have a video list, use centralized playFromList
        if let list = videoList, let index = videoIndex {
            env.queueManager.playFromList(
                videos: list,
                index: index,
                queueSource: queueSource,
                sourceLabel: sourceLabel,
                startTime: time
            )
        } else if time > 0 {
            env.playerService.openVideo(video, startTime: time)
        } else {
            env.playerService.openVideo(video)
        }
    }
}

// MARK: - View Extension

extension View {
    /// Makes the view tappable to play a video with optional context menu.
    ///
    /// - Parameters:
    ///   - video: The video to play when tapped.
    ///   - startTime: Optional start time in seconds.
    ///   - customActions: Custom actions to display at the top of the context menu.
    ///   - context: The view context for customizing built-in menu items.
    ///   - includeContextMenu: Whether to include the video context menu (default: true).
    ///   - queueSource: Optional source for continuation loading when adding to queue.
    ///   - sourceLabel: Display label for the queue source (e.g., playlist title, channel name).
    ///   - videoList: All videos in the current list (for auto-queuing subsequent videos).
    ///   - videoIndex: Index of this video in the list.
    ///   - loadMoreVideos: Callback to load more videos via continuation.
    func tappableVideo(
        _ video: Video,
        startTime: Double? = nil,
        customActions: [VideoContextAction] = [],
        context: VideoContextMenuContext = .default,
        includeContextMenu: Bool = true,
        queueSource: QueueSource? = nil,
        sourceLabel: String? = nil,
        videoList: [Video]? = nil,
        videoIndex: Int? = nil,
        loadMoreVideos: LoadMoreVideosCallback? = nil
    ) -> some View {
        modifier(TappableVideoModifier(
            video: video,
            startTime: startTime,
            customActions: customActions,
            context: context,
            includeContextMenu: includeContextMenu,
            queueSource: queueSource,
            sourceLabel: sourceLabel,
            videoList: videoList,
            videoIndex: videoIndex,
            loadMoreVideos: loadMoreVideos
        ))
    }
}
