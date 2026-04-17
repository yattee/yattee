//
//  VideoInfoView.swift
//  Yattee
//
//  Full-screen video information page with technical metadata and comments.
//

import SwiftUI
import NukeUI

/// Initialization mode for VideoInfoView - either a loaded video or just an ID to fetch.
enum VideoInfoInitMode: Sendable {
    case video(Video)
    case videoID(VideoID)
}

struct VideoInfoView: View {
    @Environment(\.appEnvironment) private var appEnvironment
    @Environment(\.videoQueueContext) private var videoQueueContext

    private let initMode: VideoInfoInitMode

    // Video loading state (for videoID mode)
    @State private var loadedVideo: Video?
    @State private var isLoadingInitialVideo = false
    @State private var initialVideoLoadError: String?
    
    // Navigation state - track current position in queue
    @State private var currentVideoIndex: Int?
    @State private var scrollViewID = UUID()
    @State private var scrollOffset: CGFloat = 0

    // Carousel scroll state (iOS only) - separate from currentVideoIndex to avoid mid-scroll updates
    #if os(iOS)
    @State private var carouselScrollPosition: Int?
    #endif
    
    // Continuation loading state
    @State private var extendedVideoList: [Video] = []
    @State private var isLoadingMoreVideos = false
    @State private var loadMoreError: String?
    
    @State private var isBookmarked = false
    @State private var showingPlaylistSheet = false
    @State private var showingCommentsSheet = false
    @State private var showingRemoveBookmarkAlert = false
    @State private var currentBookmark: Bookmark?
    @State private var bookmarkTags: [String] = []
    @State private var bookmarkNote: String = ""
    @State private var bookmarkSaveTask: Task<Void, Never>?
    @State private var isEditingBookmarkNote = false
    @State private var isEditingBookmarkTags = false
    @FocusState private var isBookmarkNoteFocused: Bool
    #if os(tvOS)
    @FocusState private var isPlayFocused: Bool
    @State private var isDescriptionScrollLocked = false
    #endif

    // Comments state (independent from PlayerState)
    @State private var comments: [Comment] = []
    @State private var commentsState: CommentsLoadState = .idle
    @State private var commentsContinuation: String?

    // Collapsible section states
    @State private var isStatsExpanded = true
    @State private var isDescriptionExpanded = true
    @State private var isRelatedExpanded = true
    @State private var isCommentsExpanded = true
    @State private var isWatchHistoryExpanded = false
    @State private var isBookmarkExpanded = true
    @State private var isDownloadExpanded = false
    @State private var isOriginalTitleExpanded = true

    // MARK: - Initializers
    
    /// Initialize with a loaded video.
    init(video: Video) {
        self.initMode = .video(video)
    }
    
    /// Initialize with a video ID to fetch.
    init(videoID: VideoID) {
        self.initMode = .videoID(videoID)
    }
    
    // MARK: - Computed Properties
    
    /// The video from init or loaded from API (nil while loading in videoID mode).
    private var video: Video? {
        switch initMode {
        case .video(let v): return v
        case .videoID: return loadedVideo
        }
    }

    // Watch history state
    @State private var watchEntry: WatchEntry?

    // Download state
    @State private var download: Download?
    @State private var showingDownloadSheet = false
    @State private var isEnqueuingDownload = false
    @State private var showingRemoveDownloadConfirmation = false
    
    // Resume action sheet state
    @State private var resumeSheetData: ResumeSheetData?
    
    // Video details cache - stores full video details loaded from API
    @State private var loadedVideoDetails: [String: Video] = [:]
    @State private var isLoadingVideoDetails = false
    /// Combined video list including originally loaded videos and extended videos from continuation
    private var allVideos: [Video]? {
        guard let originalList = videoQueueContext?.videoList else { return nil }
        return originalList + extendedVideoList
    }
    
    /// The base video from queue or init parameter (before details are loaded).
    /// Returns nil only when in videoID mode and video hasn't loaded yet.
    private var baseVideo: Video? {
        if videoQueueContext != nil,
           let index = currentVideoIndex,
           let list = allVideos,
           index >= 0 && index < list.count {
            return list[index]
        }
        return video
    }
    
    /// The video currently being displayed - prefers cached full details if available.
    /// Returns nil only when in videoID mode and video hasn't loaded yet.
    private var displayedVideo: Video? {
        guard let base = baseVideo else { return nil }
        return loadedVideoDetails[base.id.videoID] ?? base
    }

    private var accentColor: Color {
        appEnvironment?.settingsManager.accentColor.color ?? .accentColor
    }

    private var dataManager: DataManager? { appEnvironment?.dataManager }
    private var contentService: ContentService? { appEnvironment?.contentService }
    private var instancesManager: InstancesManager? { appEnvironment?.instancesManager }
    private var navigationCoordinator: NavigationCoordinator? { appEnvironment?.navigationCoordinator }
    private var playerService: PlayerService? { appEnvironment?.playerService }
    private var queueManager: QueueManager? { appEnvironment?.queueManager }
    #if !os(tvOS)
    private var downloadManager: DownloadManager? { appEnvironment?.downloadManager }
    #endif

    /// Returns the first enabled Yattee Server instance URL, if any.
    private var yatteeServerURL: URL? {
        instancesManager?.yatteeServerInstances.first { $0.isEnabled }?.url
    }

    /// Whether this video is from YouTube (global YouTube provider).
    private var isYouTube: Bool {
        guard let video = displayedVideo else { return false }
        if case .global(let provider) = video.id.source {
            return provider == ContentSource.youtubeProvider
        }
        return false
    }

    /// Whether comments are supported for this video source.
    private var supportsComments: Bool {
        // Only YouTube videos support comments via Invidious API
        isYouTube
    }

    /// Whether the description section should be visible.
    private var shouldShowDescriptionSection: Bool {
        guard !isLoadingVideoDetails else { return true }
        guard let description = displayedVideo?.description else { return false }
        return !description.isEmpty
    }

    /// Whether the stats section should be visible.
    /// Duration alone does not warrant showing stats.
    private var shouldShowStatsSection: Bool {
        guard let video = displayedVideo else { return false }
        return video.viewCount != nil || video.likeCount != nil || video.formattedPublishedDate != nil
    }

    /// Whether the original title section should be visible (when DeArrow replaces title).
    private var shouldShowOriginalTitleSection: Bool {
        guard let video = displayedVideo,
              let settingsManager = appEnvironment?.settingsManager,
              settingsManager.deArrowEnabled,
              settingsManager.deArrowReplaceTitles,
              let provider = appEnvironment?.deArrowBrandingProvider,
              provider.title(for: video) != nil else {
            return false
        }
        return true
    }

    /// Display string for the video source (YouTube, PeerTube • instance, or MediaSourceType • share name).
    private var videoSourceDisplay: String? {
        guard let video = displayedVideo else { return nil }
        switch video.id.source {
        case .global(let provider):
            return provider.prefix(1).uppercased() + provider.dropFirst()
        case .federated(_, let instance):
            return "PeerTube • \(instance.host ?? instance.absoluteString)"
        case .extracted(let extractor, _):
            // For media sources, show type + share name
            if let mediaSourceID = video.mediaSourceID,
               let mediaSource = appEnvironment?.mediaSourcesManager.source(byID: mediaSourceID) {
                return "\(mediaSource.type.displayName) • \(mediaSource.name)"
            }
            // Fallback for other extracted sources (e.g., Bilibili, Vimeo)
            let formatted = extractor.replacingOccurrences(of: "_", with: " ")
            return formatted.prefix(1).uppercased() + formatted.dropFirst()
        }
    }

    /// Navigation title - uses source label if available, otherwise video title
    private var displayTitle: String {
        videoQueueContext?.sourceLabel ?? displayedVideo?.title ?? ""
    }
    
    /// Thumbnail width - larger for carousel on iOS
    private var thumbnailWidth: CGFloat {
        #if os(iOS)
        return videoQueueContext != nil ? 280 : 240
        #else
        return 240
        #endif
    }
    
    /// Dynamic label for the play button - shows "Continue at XX:XX" if video has meaningful progress
    /// and resume setting is continueWatching or ask.
    private var playButtonLabel: String {
        guard let video = displayedVideo,
              let savedProgress = dataManager?.watchProgress(for: video.id.videoID),
              savedProgress >= 5,
              video.duration > 0,
              savedProgress < video.duration * 0.9 else {
            return String(localized: "video.context.play")
        }
        
        let resumeAction = appEnvironment?.settingsManager.resumeAction ?? .continueWatching
        switch resumeAction {
        case .continueWatching, .ask:
            return String(localized: "resume.action.continueAt \(savedProgress.formattedAsTimestamp)")
        case .startFromBeginning:
            return String(localized: "video.context.play")
        }
    }

    var body: some View {
        Group {
            if isLoadingInitialVideo {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = initialVideoLoadError {
                videoLoadErrorView(error)
            } else if displayedVideo != nil {
                videoContent
            }
        }
        .task {
            await loadInitialVideoIfNeeded()
        }
        #if os(tvOS)
        .navigationTitle("")
        #else
        .navigationTitle(displayTitle)
        #endif
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .onAppear {
            // Initialize current index from queue context
            if currentVideoIndex == nil, let context = videoQueueContext {
                currentVideoIndex = context.videoIndex
            }
            
            // Load initial video data (only if video is already loaded)
            guard displayedVideo != nil else { return }
            #if !os(tvOS)
            loadVideoData()
            #else
            if let video = displayedVideo {
                isBookmarked = dataManager?.isBookmarked(videoID: video.id.videoID) ?? false
                if isBookmarked, let bookmark = dataManager?.bookmark(for: video.id.videoID) {
                    currentBookmark = bookmark
                    bookmarkTags = bookmark.tags
                    bookmarkNote = bookmark.note ?? ""
                } else {
                    currentBookmark = nil
                    bookmarkTags = []
                    bookmarkNote = ""
                }
                watchEntry = dataManager?.watchEntry(for: video.id.videoID)
            }
            loadComments()
            DispatchQueue.main.async {
                isPlayFocused = true
            }
            #endif

            // Load full video details from API
            Task {
                await loadVideoDetails()
            }
        }
        .onDisappear {
            // Cancel any pending bookmark save
            bookmarkSaveTask?.cancel()
        }
        .onChange(of: currentVideoIndex) { oldValue, newValue in
            // Skip if this is the initial value setting (handled by onAppear)
            guard oldValue != nil else { return }

            // Reset state when navigating to different video
            showingCommentsSheet = false
            showingPlaylistSheet = false
            showingDownloadSheet = false
            showingRemoveBookmarkAlert = false
            bookmarkSaveTask?.cancel()
            comments = []
            commentsState = .idle
            commentsContinuation = nil
            scrollViewID = UUID() // Reset scroll position
            // Don't reset scrollOffset here - let the new scroll view report its geometry
            // Resetting to 0 causes the blur to jump to an incorrect position briefly
            
            // Load new video data
            #if !os(tvOS)
            loadVideoData()
            
            // Pre-load more videos if we're at 95% of the list
            if shouldPreloadMore {
                Task {
                    await loadMoreVideos()
                }
            }
            #else
            if let video = displayedVideo {
                isBookmarked = dataManager?.isBookmarked(videoID: video.id.videoID) ?? false
                if isBookmarked, let bookmark = dataManager?.bookmark(for: video.id.videoID) {
                    currentBookmark = bookmark
                    bookmarkTags = bookmark.tags
                    bookmarkNote = bookmark.note ?? ""
                } else {
                    currentBookmark = nil
                    bookmarkTags = []
                    bookmarkNote = ""
                }
                watchEntry = dataManager?.watchEntry(for: video.id.videoID)
            }
            loadComments()
            DispatchQueue.main.async {
                isPlayFocused = true
            }
            #endif

            // Load full video details from API
            Task {
                await loadVideoDetails()
            }
        }
        .sheet(isPresented: $showingPlaylistSheet) {
            if let video = displayedVideo {
                PlaylistSelectorSheet(video: video)
            }
        }
        #if os(tvOS)
        .fullScreenCover(isPresented: $showingCommentsSheet) {
            commentsSheetContent
        }
        #else
        .sheet(isPresented: $showingCommentsSheet) {
            commentsSheetContent
        }
        #endif
        .sheet(item: $resumeSheetData) { data in
            ResumeActionSheet(
                video: data.video,
                resumeTime: data.resumeTime,
                onContinue: { playVideoWithStartTime(data.resumeTime) },
                onStartOver: { playVideoWithStartTime(0) }
            )
        }
        #if !os(tvOS)
        .sheet(isPresented: $showingDownloadSheet) {
            if let video = displayedVideo {
                DownloadQualitySheet(video: video)
            }
        }
        .onChange(of: downloadManager?.completedDownloads) { _, newValue in
            // Update download state when completedDownloads changes
            if let video = displayedVideo {
                download = downloadManager?.download(for: video.id)
            }
        }
        .onChange(of: downloadManager?.activeDownloads) { _, newValue in
            // Update download state when activeDownloads changes (download started)
            if download == nil, let video = displayedVideo {
                download = downloadManager?.download(for: video.id)
            }
        }
        #endif
        .alert(String(localized: "bookmark.remove.title"), isPresented: $showingRemoveBookmarkAlert) {
            Button(String(localized: "common.cancel"), role: .cancel) {}
            Button(String(localized: "bookmark.remove.confirm"), role: .destructive) {
                removeBookmark()
            }
        } message: {
            Text(String(localized: "bookmark.remove.message"))
        }
        #if !os(tvOS)
        .alert(String(localized: "videoInfo.download.remove.title"), isPresented: $showingRemoveDownloadConfirmation) {
            Button(String(localized: "common.cancel"), role: .cancel) {}
            Button(String(localized: "videoInfo.download.remove.confirm"), role: .destructive) {
                if let download = download {
                    Task {
                        await downloadManager?.delete(download)
                    }
                }
            }
        } message: {
            Text(String(localized: "videoInfo.download.remove.message"))
        }
        #endif
    }
    
    // MARK: - Video Content
    
    /// Main video content view (shown after video is loaded).
    @ViewBuilder
    private var videoContent: some View {
        #if os(tvOS)
        tvOSVideoContent
        #else
        iOSVideoContent
        #endif
    }

    #if !os(tvOS)
    @ViewBuilder
    private var iOSVideoContent: some View {
        GeometryReader { geometry in
            let safeAreaTop = geometry.safeAreaInsets.top

            ZStack(alignment: .top) {
                // Blurred background layer - moves up with scroll to keep edge hidden
                // Add safeAreaTop to offset so background starts moving immediately when user scrolls from rest
                // (at rest, scrollOffset ≈ -safeAreaTop, so offset = max(0, 0) = 0)
                // Extra top padding keeps the clipped top edge hidden above the visible area during scroll
                let extraTopPadding: CGFloat = 150

                let blurOffset: CGFloat = -max(scrollOffset + safeAreaTop, 0) - extraTopPadding

                Color.clear
                    .frame(height: headerBackgroundHeight + extraTopPadding)
                    .frame(maxWidth: .infinity)
                    .background(alignment: .bottom) {
                        blurredThumbnailBackground
                    }
                    .clipped()
                    .offset(y: blurOffset)
                    .animation(.easeOut(duration: 0.2), value: scrollOffset)
                    .ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        // Header with thumbnail, title, and channel
                        headerSection

                        // Action buttons
                        actionButtons

                        // Bookmark details section (only show if bookmarked)
                        if isBookmarked, let bookmark = currentBookmark {
                            Divider()
                                .padding(.horizontal)

                            bookmarkDetailsSection(bookmark)
                        }

                        // Description section (collapsible) - only show if description available
                        if shouldShowDescriptionSection {
                            Divider()
                                .padding(.horizontal)

                            descriptionSection
                        }

                        // Original title section - only show when DeArrow title is active
                        if shouldShowOriginalTitleSection {
                            Divider()
                                .padding(.horizontal)

                            originalTitleSection
                        }

                        // Stats section (collapsible) - only show if meaningful stats exist
                        if shouldShowStatsSection {
                            Divider()
                                .padding(.horizontal)

                            statsSection
                        }

                        Divider()
                            .padding(.horizontal)

                        // Comments section (collapsible)
                        commentsSection

                        // Related videos section (collapsible, only shown if videos exist)
                        if let relatedVideos = displayedVideo?.relatedVideos, !relatedVideos.isEmpty {
                            Divider()
                                .padding(.horizontal)

                            relatedVideosSection(relatedVideos)
                        }


                        // Watch history section (only show if entry exists)
                        if let entry = watchEntry {
                            Divider()
                                .padding(.horizontal)

                            watchHistorySection(entry)
                        }

                        #if !os(tvOS)
                        // Download section (only show if downloaded)
                        if let download = download, download.status == .completed {
                            Divider()
                                .padding(.horizontal)

                            downloadSection(download)
                        }
                        #endif
                    }
                    .id(currentVideoIndex) // Force re-render when video changes
                }
                #if !os(tvOS)
                .scrollDismissesKeyboard(.interactively)
                #endif
                .modifier(VideoInfoScrollOffsetModifier(scrollOffset: $scrollOffset))
                // Navigation buttons overlay - floats above scrolling content in ZStack (macOS only)
                #if os(macOS)
                if videoQueueContext != nil {
                    navigationButtonsOverlay
                }
                #endif
            }
        }
    }
    #endif

    #if os(tvOS)
    // MARK: - tvOS Two-Column Layout

    @ViewBuilder
    private var tvOSVideoContent: some View {
        GeometryReader { geometry in
            let leftWidth = geometry.size.width * 0.30
            HStack(alignment: .top, spacing: 40) {
                tvOSLeftColumn
                    .frame(width: leftWidth, alignment: .leading)
                    .focusSection()

                tvOSRightColumn
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .focusSection()
            }
            .padding(.horizontal, 60)
            .padding(.vertical, 40)
        }
    }

    private var tvOSLeftColumn: some View {
        VStack(alignment: .leading, spacing: 24) {
            if let video = displayedVideo {
                tvOSThumbnail(for: video)
                    .frame(maxWidth: .infinity)
                    .aspectRatio(16.0 / 9.0, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                Text(video.displayTitle(using: appEnvironment?.deArrowBrandingProvider))
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)

                tvOSChannelRow(for: video)

                Button(action: playVideo) {
                    Label(playButtonLabel, systemImage: "play.fill")
                        .frame(maxWidth: .infinity, minHeight: 60)
                        .font(.headline)
                }
                .buttonStyle(.borderedProminent)
                .focused($isPlayFocused)

                Button {
                    showingPlaylistSheet = true
                } label: {
                    Label(String(localized: "video.context.addToPlaylist"), systemImage: "text.badge.plus")
                        .frame(maxWidth: .infinity, minHeight: 50)
                }
                .buttonStyle(.bordered)

                Button {
                    toggleBookmark()
                } label: {
                    Label(
                        isBookmarked ? String(localized: "video.removeBookmark") : String(localized: "video.bookmark"),
                        systemImage: isBookmarked ? "bookmark.fill" : "bookmark"
                    )
                    .frame(maxWidth: .infinity, minHeight: 50)
                }
                .buttonStyle(.bordered)
            }

            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private func tvOSThumbnail(for video: Video) -> some View {
        let deArrowURL = appEnvironment?.deArrowBrandingProvider.thumbnailURL(for: video)
        let thumbnailURL = deArrowURL ?? video.bestThumbnail?.url

        LazyImage(url: thumbnailURL) { state in
            if let image = state.image {
                image
                    .resizable()
                    .aspectRatio(16.0 / 9.0, contentMode: .fill)
            } else {
                Rectangle()
                    .fill(.quaternary)
                    .overlay {
                        Text(video.displayTitle(using: appEnvironment?.deArrowBrandingProvider))
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .lineLimit(3)
                            .padding(8)
                    }
            }
        }
    }

    @ViewBuilder
    private func tvOSChannelRow(for video: Video) -> some View {
        if video.author.hasRealChannelInfo {
            Button {
                navigationCoordinator?.navigateToChannel(for: video)
            } label: {
                channelRowContent(for: video)
            }
            .buttonStyle(.plain)
        } else {
            channelRowContent(for: video)
        }
    }

    private var tvOSRightColumn: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if !isDescriptionScrollLocked, isBookmarked, let bookmark = currentBookmark {
                        bookmarkDetailsSection(bookmark)

                        Divider()
                            .padding(.horizontal)
                            .padding(.vertical, 16)
                    }

                    if isLoadingVideoDetails {
                        HStack {
                            Spacer()
                            ProgressView()
                            Spacer()
                        }
                        .frame(height: 450)
                        .padding(.horizontal)

                        Divider()
                            .padding(.horizontal)
                            .padding(.vertical, 16)
                    } else if let description = displayedVideo?.description, !description.isEmpty {
                        TVScrollableDescription(
                            description: description,
                            isScrollLocked: $isDescriptionScrollLocked,
                            showsHeader: false
                        )
                        .frame(height: isDescriptionScrollLocked ? geometry.size.height : 450)
                        .padding(.horizontal)

                        if !isDescriptionScrollLocked {
                            Divider()
                                .padding(.horizontal)
                                .padding(.vertical, 16)
                        }
                    }

                    if !isDescriptionScrollLocked {
                        if shouldShowOriginalTitleSection {
                            originalTitleSection

                            Divider()
                                .padding(.horizontal)
                                .padding(.vertical, 16)
                        }

                        if shouldShowStatsSection {
                            statsSection

                            Divider()
                                .padding(.horizontal)
                                .padding(.vertical, 16)
                        }

                        commentsSection

                        if let relatedVideos = displayedVideo?.relatedVideos, !relatedVideos.isEmpty {
                            Divider()
                                .padding(.horizontal)
                                .padding(.vertical, 16)

                            relatedVideosSection(relatedVideos)
                        }

                        if let entry = watchEntry {
                            Divider()
                                .padding(.horizontal)
                                .padding(.vertical, 16)

                            watchHistorySection(entry)
                        }
                    }
                }
                .padding(.vertical, 20)
                .id(currentVideoIndex)
                .animation(.easeInOut(duration: 0.25), value: isDescriptionScrollLocked)
            }
            .scrollClipDisabled()
            .scrollDisabled(isDescriptionScrollLocked)
        }
    }
    #endif

    /// Error view shown when video fails to load (videoID init mode only).
    @ViewBuilder
    private func videoLoadErrorView(_ message: String) -> some View {
        ContentUnavailableView {
            Label(String(localized: "video.error.title"), systemImage: "exclamationmark.triangle")
        } description: {
            Text(message)
        } actions: {
            Button(String(localized: "common.retry")) {
                Task {
                    await loadInitialVideoIfNeeded()
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Header Section

    private var headerSection: some View {
        VStack(alignment: .center, spacing: 0) {
            #if os(iOS)
            if videoQueueContext != nil, let videos = allVideos, !videos.isEmpty {
                // iOS with queue: full-width carousel with peek thumbnails
                thumbnailCarousel
            } else {
                // iOS without queue or empty queue: just the thumbnail
                singleVideoCard
            }
            #else
            // Non-iOS platforms: just the thumbnail
            singleVideoCard
            #endif
        }
        .padding(.top)
    }

    /// Blurred thumbnail background for ambient effect behind the header
    @ViewBuilder
    private var blurredThumbnailBackground: some View {
        BlurredImageBackground(
            url: displayedVideo.flatMap { appEnvironment?.deArrowBrandingProvider.thumbnailURL(for: $0) } ?? displayedVideo?.bestThumbnail?.url,
            videoID: displayedVideo?.id.videoID,
            blurRadius: BlurredImageBackground.platformBlurRadius,
            scale: 1.8,
            gradientColor: headerBackgroundColor,
            contentOpacity: blurredBackgroundOpacity
        )
        .frame(height: headerBackgroundHeight)
    }

    /// Calculated height for the blurred background based on content
    private var headerBackgroundHeight: CGFloat {
        // Thumbnail height + title area + channel area + padding
        let titleHeight: CGFloat = 50  // Title with line limit 2
        let channelHeight: CGFloat = 60 // Avatar + name + subscribers
        let padding: CGFloat = 60      // Top and bottom padding
        return thumbnailHeight + titleHeight + channelHeight + padding
    }

    /// Opacity for the blurred background that fades as user scrolls down
    private var blurredBackgroundOpacity: Double {
        let fadeDistance = headerBackgroundHeight * 0.5  // Fade 2x faster to hide hard edge before it's visible
        let progress = min(max(scrollOffset / fadeDistance, 0), 1)
        return 1.0 - progress
    }

    /// Platform-specific background color for gradient fade
    private var headerBackgroundColor: Color {
        #if os(iOS)
        Color(uiColor: .systemBackground)
        #elseif os(macOS)
        Color(nsColor: .windowBackgroundColor)
        #else
        Color.black
        #endif
    }
    
    /// Single video card without carousel (used when no queue context or non-iOS)
    @ViewBuilder
    private var singleVideoCard: some View {
        if let video = displayedVideo {
            videoCard(for: video, isLoadingMore: false, showTitle: true, isCurrent: true)
                .frame(maxWidth: .infinity)
                .padding(.horizontal)
        }
    }
    
    /// Spacing between carousel items
    private var carouselSpacing: CGFloat { 16 }
    
    /// Opacity for adjacent thumbnails (non-current videos)
    private var peekOpacity: Double { 0.5 }
    
    /// Full-width thumbnail carousel with peek effect (iOS only)
    /// Uses horizontal ScrollView with scrollTargetBehavior for native gesture handling
    @ViewBuilder
    private var thumbnailCarousel: some View {
        #if os(iOS)
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: carouselSpacing) {
                    if let videos = allVideos {
                        ForEach(Array(videos.enumerated()), id: \.element.id) { index, video in
                            let isCurrent = index == currentVideoIndex
                            // Use original video for thumbnail (stable), get author from detailed video for avatar
                            let authorSource = loadedVideoDetails[video.id.videoID]
                            videoCard(for: video, authorFrom: authorSource, isLoadingMore: isLoadingMoreVideos && isCurrent, showTitle: true, isCurrent: isCurrent)
                                .opacity(isCurrent ? 1.0 : peekOpacity)
                                .containerRelativeFrame(.horizontal)
                                .id(index)
                                .onTapGesture {
                                    if !isCurrent {
                                        withAnimation(.easeInOut(duration: 0.3)) {
                                            carouselScrollPosition = index
                                            currentVideoIndex = index
                                        }
                                    }
                                }
                        }
                        
                        // Placeholder for loading more
                        if videoQueueContext?.canLoadMore == true {
                            videoCardPlaceholder(isLoading: isLoadingMoreVideos)
                                .opacity(peekOpacity)
                                .containerRelativeFrame(.horizontal)
                                .id("load-more-placeholder")
                        }
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.viewAligned(limitBehavior: .alwaysByOne))
            .scrollPosition(id: $carouselScrollPosition)
            .onScrollPhaseChange { oldPhase, newPhase in
                // Only update currentVideoIndex when scrolling ends (user lifts finger)
                if newPhase == .idle, let newIndex = carouselScrollPosition, newIndex != currentVideoIndex {
                    currentVideoIndex = newIndex
                }
            }
            .onChange(of: currentVideoIndex) { oldValue, newValue in
                // Sync scroll position when currentVideoIndex changes from outside (e.g., onAppear)
                if let newValue, newValue != carouselScrollPosition {
                    carouselScrollPosition = newValue
                    proxy.scrollTo(newValue, anchor: .center)
                }
            }
            .onAppear {
                // Initialize scroll position
                if carouselScrollPosition == nil, let index = currentVideoIndex {
                    carouselScrollPosition = index
                }
            }
        }
        #endif
    }
    
    /// Height of thumbnail based on width and 16:9 aspect ratio
    private var thumbnailHeight: CGFloat {
        thumbnailWidth * 9 / 16
    }
    
    /// A single video card with thumbnail, title, and channel info
    /// - Parameters:
    ///   - video: The video to display (used for thumbnail - stable reference)
    ///   - authorFrom: Optional video to get author info from (for avatar URL from detailed video)
    ///   - isLoadingMore: Whether to show loading overlay for continuation loading
    ///   - showTitle: Whether to show the title and channel (animates in/out)
    ///   - isCurrent: Whether this is the currently selected video (thumbnail tap plays video)
    private func videoCard(for video: Video, authorFrom: Video? = nil, isLoadingMore: Bool, showTitle: Bool, isCurrent: Bool) -> some View {
        let deArrowURL = appEnvironment?.deArrowBrandingProvider.thumbnailURL(for: video)
        let bestThumb = video.bestThumbnail
        let thumbnailURL = deArrowURL ?? bestThumb?.url
        return VStack(spacing: 12) {
            // Thumbnail with loading overlay
            ZStack {
                LazyImage(url: thumbnailURL) { state in
                    if let image = state.image {
                        image
                            .resizable()
                            .aspectRatio(16/9, contentMode: .fill)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    } else {
                        Rectangle()
                            .fill(.quaternary)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .overlay {
                                Text(video.displayTitle(using: appEnvironment?.deArrowBrandingProvider))
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.center)
                                    .lineLimit(3)
                                    .padding(8)
                            }
                    }
                }
                .aspectRatio(16/9, contentMode: .fit)
                .frame(width: thumbnailWidth)

                // Loading overlay when fetching more videos (continuation)
                if isLoadingMore {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(.black.opacity(0.4))
                        .frame(width: thumbnailWidth)
                        .aspectRatio(16/9, contentMode: .fit)
                    
                    ProgressView()
                        .tint(.white)
                }
            }
            .onTapGesture {
                if isCurrent {
                    playVideo()
                }
            }
            
            // Title
            Text(video.displayTitle(using: appEnvironment?.deArrowBrandingProvider))
                .font(.headline)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(width: thumbnailWidth)
                .opacity(showTitle ? 1.0 : 0.0)
            
            // Channel row (horizontal) - only tappable if we have real channel info
            // Use authorFrom for author info (includes avatar URL) if available
            Group {
                let authorVideo = authorFrom ?? video
                if authorVideo.author.hasRealChannelInfo {
                    Button {
                        navigationCoordinator?.navigateToChannel(for: authorVideo)
                    } label: {
                        channelRowContent(for: authorVideo)
                    }
                    .buttonStyle(.plain)
                } else {
                    channelRowContent(for: authorVideo)
                }
            }
            .opacity(showTitle ? 1.0 : 0.0)
        }
    }

    /// Channel row content used in both tappable and non-tappable variants
    private func channelRowContent(for video: Video) -> some View {
        let enrichedAuthor = appEnvironment.map { video.author.enriched(using: $0.dataManager) } ?? video.author
        return HStack(spacing: 10) {
            ChannelAvatarView(
                author: enrichedAuthor,
                size: 40,
                yatteeServerURL: yatteeServerURL,
                source: video.authorSource
            )

            VStack(alignment: .leading, spacing: 2) {
                Text(enrichedAuthor.name)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(1)

                Group {
                    if let subscribers = enrichedAuthor.formattedSubscriberCount {
                        Text(subscribers)
                    } else if isLoadingVideoDetails && video.supportsAPIStats {
                        Text("1.2M subscribers")
                            .redacted(reason: .placeholder)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
        }
    }

    /// Placeholder card shown when loading more videos
    private func videoCardPlaceholder(isLoading: Bool) -> some View {
        VStack(spacing: 12) {
            // Thumbnail placeholder
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(.quaternary)
                    .aspectRatio(16/9, contentMode: .fit)
                    .frame(width: thumbnailWidth)
                
                if isLoading {
                    ProgressView()
                        .tint(.secondary)
                }
            }
            
            // Title placeholder
            VStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(.quaternary)
                    .frame(width: thumbnailWidth * 0.8, height: 16)
                
                RoundedRectangle(cornerRadius: 4)
                    .fill(.quaternary)
                    .frame(width: thumbnailWidth * 0.5, height: 12)
            }
            
            // Channel placeholder
            VStack(spacing: 4) {
                // Avatar placeholder (circle)
                Circle()
                    .fill(.quaternary)
                    .frame(width: 56, height: 56)
                
                // Name placeholder
                RoundedRectangle(cornerRadius: 4)
                    .fill(.quaternary)
                    .frame(width: thumbnailWidth * 0.4, height: 14)
                
                // Subscriber count placeholder
                RoundedRectangle(cornerRadius: 4)
                    .fill(.quaternary)
                    .frame(width: thumbnailWidth * 0.25, height: 12)
            }
        }
        .frame(width: thumbnailWidth)
    }

    // MARK: - Action Buttons

    /// Vertical action button with large icon on top and text below
    private func verticalActionButton(
        icon: String,
        label: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 18))
                Text(label)
                    .font(.caption)
            }
            .frame(maxWidth: .infinity, minHeight: 50)
        }
        .buttonStyle(.borderedProminent)
    }

    private var actionButtons: some View {
        VStack(spacing: 12) {
            #if !os(tvOS)
            // Play, Download and Share (vertical layout)
            HStack(spacing: 12) {
                // Play button
                verticalActionButton(
                    icon: "play.fill",
                    label: String(localized: "video.context.play"),
                    action: playVideo
                )

                // Download button
                verticalDownloadActionButton

                // Share button
                if let video = displayedVideo {
                    ShareLink(item: video.shareURL) {
                        VStack(spacing: 6) {
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 18))
                            Text(String(localized: "video.share"))
                                .font(.caption)
                        }
                        .frame(maxWidth: .infinity, minHeight: 50)
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            #endif

            // Add to Playlist and Bookmark
            HStack(spacing: 12) {
                Button {
                    showingPlaylistSheet = true
                } label: {
                    Label(String(localized: "video.context.addToPlaylist"), systemImage: "text.badge.plus")
                        .frame(maxWidth: .infinity)
                        .font(.subheadline)
                }
                .buttonStyle(.bordered)

                Button {
                    toggleBookmark()
                } label: {
                    Label(
                        isBookmarked ? String(localized: "video.removeBookmark") : String(localized: "video.bookmark"),
                        systemImage: isBookmarked ? "bookmark.fill" : "bookmark"
                    )
                    .frame(maxWidth: .infinity)
                    .font(.subheadline)
                }
                .buttonStyle(.bordered)
            }
        }
        .fontWeight(.semibold)
        .frame(maxWidth: 400)
        .frame(maxWidth: .infinity)
        .padding(.horizontal)
        .padding(.vertical, 12)
    }

    #if !os(tvOS)
    /// Vertical download action button with four states: default, enqueueing, downloading, downloaded
    @ViewBuilder
    private var verticalDownloadActionButton: some View {
        let isDownloaded = download?.status == .completed
        let isDownloading = displayedVideo.flatMap { downloadManager?.isDownloading($0.id) } ?? false

        if isDownloaded {
            // Downloaded state - tap to show delete confirmation
            Button(role: .destructive) {
                showingRemoveDownloadConfirmation = true
            } label: {
                VStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 18))
                    Text(String(localized: "video.downloaded"))
                        .font(.caption)
                }
                .frame(maxWidth: .infinity, minHeight: 50)
            }
            .buttonStyle(.borderedProminent)
        } else if isDownloading || isEnqueuingDownload {
            // Downloading/enqueueing state - shows progress
            Button {
                // No action while downloading
            } label: {
                VStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.regular)
                    if isEnqueuingDownload {
                        Text(String(localized: "video.downloading"))
                            .allowsTightening(true)
                            .font(.caption)
                    } else if let video = displayedVideo,
                              let progress = downloadManager?.downloadProgressByVideo[video.id],
                              !progress.isIndeterminate {
                        Text("\(Int(progress.progress * 100))%")
                            .font(.caption)
                            .monospacedDigit()
                    } else {
                        Text(String(localized: "video.downloading"))
                            .allowsTightening(true)
                            .font(.caption)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 50)
            }
            .buttonStyle(.borderedProminent)
            .disabled(true)
        } else if let video = displayedVideo {
            // Default state - download button
            Button {
                startDownload(for: video)
            } label: {
                VStack(spacing: 6) {
                    Image(systemName: "arrow.down.circle")
                        .font(.system(size: 18))
                    Text(String(localized: "video.download"))
                        .font(.caption)
                }
                .frame(maxWidth: .infinity, minHeight: 50)
            }
            .buttonStyle(.borderedProminent)
        }
    }

    /// Starts a download either automatically or by showing the quality sheet.
    private func startDownload(for video: Video) {
        guard let appEnvironment else {
            showingDownloadSheet = true
            return
        }

        // Media source videos (SMB/WebDAV/local) use direct file URLs - no API call needed
        if video.isFromMediaSource {
            isEnqueuingDownload = true
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
                await MainActor.run {
                    isEnqueuingDownload = false
                }
            }
            return
        }

        let downloadSettings = appEnvironment.downloadSettings

        // Check if auto-download mode
        if downloadSettings.preferredDownloadQuality != .ask,
           let instance = appEnvironment.instancesManager.instance(for: video) {
            isEnqueuingDownload = true
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
                await MainActor.run {
                    isEnqueuingDownload = false
                }
            }
        } else {
            showingDownloadSheet = true
        }
    }

    private func downloadSection(_ download: Download) -> some View {
        CollapsibleSection(title: String(localized: "videoInfo.section.download"), isExpanded: $isDownloadExpanded) {
            VStack(alignment: .leading, spacing: 12) {
                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ], spacing: 12) {
                    // Quality
                    infoRow(
                        label: String(localized: "videoInfo.download.quality"),
                        value: download.quality
                    )

                    // File size
                    infoRow(
                        label: String(localized: "videoInfo.download.fileSize"),
                        value: formatBytes(download.totalBytes)
                    )

                    // Video codec
                    if let codec = download.videoCodec {
                        infoRow(
                            label: String(localized: "videoInfo.download.videoCodec"),
                            value: codec.uppercased()
                        )
                    }

                    // Audio codec
                    if let codec = download.audioCodec {
                        infoRow(
                            label: String(localized: "videoInfo.download.audioCodec"),
                            value: codec.uppercased()
                        )
                    }

                    // Downloaded at
                    if let completedAt = download.completedAt {
                        infoRow(
                            label: String(localized: "videoInfo.download.downloadedAt"),
                            value: completedAt.formatted(date: .abbreviated, time: .shortened)
                        )
                    }

                    // Bitrates
                    if let videoBitrate = download.videoBitrate {
                        infoRow(
                            label: String(localized: "videoInfo.download.videoBitrate"),
                            value: formatBitrate(videoBitrate)
                        )
                    }

                    if let audioBitrate = download.audioBitrate {
                        infoRow(
                            label: String(localized: "videoInfo.download.audioBitrate"),
                            value: formatBitrate(audioBitrate)
                        )
                    }
                }

                Button(role: .destructive) {
                    showingRemoveDownloadConfirmation = true
                } label: {
                    Label(String(localized: "videoInfo.download.remove"), systemImage: "trash")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(.red)
                .padding(.top, 8)
            }
        }
    }

    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }

    private func formatBitrate(_ bitrate: Int) -> String {
        if bitrate >= 1_000_000 {
            return String(format: "%.1f Mbps", Double(bitrate) / 1_000_000)
        } else {
            return String(format: "%d kbps", bitrate / 1000)
        }
    }
    #endif
    // MARK: - Stats Section

    @ViewBuilder
    private var statsSection: some View {
        if let video = displayedVideo {
            CollapsibleSection(title: String(localized: "videoInfo.section.stats"), isExpanded: $isStatsExpanded) {
                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ], spacing: 12) {
                    if let viewCount = video.viewCount {
                        infoRow(
                            label: String(localized: "videoInfo.views"),
                            value: CountFormatter.compact(viewCount)
                        )
                    }

                    if let likeCount = video.likeCount {
                        infoRow(
                            label: String(localized: "videoInfo.likes"),
                            value: CountFormatter.compact(likeCount)
                        )
                    }

                    if let publishedText = video.formattedPublishedDate {
                        infoRow(
                            label: String(localized: "videoInfo.published"),
                            value: publishedText
                        )
                    }

                    infoRow(
                        label: String(localized: "videoInfo.duration"),
                        value: video.formattedDuration
                    )

                    if let source = videoSourceDisplay {
                        infoRow(
                            label: String(localized: "videoInfo.source"),
                            value: source
                        )
                    }
                }
            }
        }
    }

    // MARK: - Watch History Section

    private func watchHistorySection(_ entry: WatchEntry) -> some View {
        CollapsibleSection(title: String(localized: "videoInfo.section.watchHistory"), isExpanded: $isWatchHistoryExpanded) {
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 12) {
                // First watched
                infoRow(
                    label: String(localized: "videoInfo.firstWatched"),
                    value: entry.createdAt.formatted(date: .abbreviated, time: .shortened)
                )

                // Last watched
                infoRow(
                    label: String(localized: "videoInfo.lastWatched"),
                    value: entry.updatedAt.formatted(date: .abbreviated, time: .shortened)
                )

                // Progress
                VStack(alignment: .leading, spacing: 4) {
                    Text(String(localized: "videoInfo.progress"))
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 8) {
                        // Progress bar
                        GeometryReader { geometry in
                            ZStack(alignment: .leading) {
                                Capsule()
                                    .fill(.quaternary)
                                    .frame(height: 6)

                                Capsule()
                                    .fill(entry.isFinished ? Color.green : accentColor)
                                    .frame(width: geometry.size.width * entry.progress, height: 6)
                            }
                        }
                        .frame(height: 6)

                        // Percentage
                        Text("\(Int(entry.progress * 100))%")
                            .font(.caption)
                            .fontWeight(.medium)
                            .monospacedDigit()
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // Completed
                VStack(alignment: .leading, spacing: 2) {
                    Text(String(localized: "videoInfo.completed"))
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if let finishedAt = entry.finishedAt {
                        Text(finishedAt.formatted(date: .abbreviated, time: .shortened))
                            .font(.subheadline)
                            .fontWeight(.medium)
                    } else if entry.isFinished {
                        Text(String(localized: "common.yes"))
                            .font(.subheadline)
                            .fontWeight(.medium)
                    } else {
                        Text(String(localized: "videoInfo.notCompleted"))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // MARK: - Bookmark Details Section
    
    private func bookmarkDetailsSection(_ bookmark: Bookmark) -> some View {
        CollapsibleSection(title: String(localized: "videoInfo.section.bookmarkDetails"), isExpanded: $isBookmarkExpanded) {
            VStack(alignment: .leading, spacing: 12) {
                // Bookmarked date
                VStack(alignment: .leading, spacing: 2) {
                    Text(String(localized: "videoInfo.bookmarkedAt"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    Text(bookmark.createdAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.subheadline)
                        .fontWeight(.medium)
                }
                
                // Tags section
                VStack(alignment: .leading, spacing: 8) {
                    Text(String(localized: "videoInfo.bookmark.tags"))
                        .font(.subheadline)
                        .fontWeight(.medium)

                    if bookmarkTags.isEmpty && !isEditingBookmarkTags {
                        Button {
                            isEditingBookmarkTags = true
                        } label: {
                            Label(String(localized: "videoInfo.bookmark.addTags"), systemImage: "plus.circle")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    } else {
                        TagInputView(tags: $bookmarkTags, isFocused: isEditingBookmarkTags)
                            .onChange(of: bookmarkTags) { _, newTags in
                                debouncedSaveBookmark()
                                if newTags.isEmpty {
                                    isEditingBookmarkTags = false
                                }
                            }
                    }
                }
                
                // Notes section
                VStack(alignment: .leading, spacing: 8) {
                    Text(String(localized: "videoInfo.bookmark.notes"))
                        .font(.subheadline)
                        .fontWeight(.medium)

                    if bookmarkNote.isEmpty && !isEditingBookmarkNote {
                        Button {
                            isEditingBookmarkNote = true
                            isBookmarkNoteFocused = true
                        } label: {
                            Label(String(localized: "videoInfo.bookmark.addNotes"), systemImage: "plus.circle")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    } else {
                        #if os(tvOS)
                        TextField(String(localized: "videoInfo.bookmark.notes"), text: $bookmarkNote, axis: .vertical)
                            .frame(minHeight: 100)
                            .font(.subheadline)
                            .onChange(of: bookmarkNote) { _, _ in
                                debouncedSaveBookmark()
                            }
                        #else
                        TextEditor(text: $bookmarkNote)
                            .focused($isBookmarkNoteFocused)
                            .frame(minHeight: 100)
                            .font(.subheadline)
                            #if os(iOS)
                            .scrollContentBackground(.hidden)
                            .background(Color(uiColor: .secondarySystemGroupedBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            #elseif os(macOS)
                            .scrollContentBackground(.hidden)
                            .background(Color(nsColor: .controlBackgroundColor))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            #endif
                            .onChange(of: bookmarkNote) { _, newValue in
                                if newValue.isEmpty {
                                    // Save immediately when cleared to prevent data loss
                                    bookmarkSaveTask?.cancel()
                                    saveBookmark()
                                } else {
                                    debouncedSaveBookmark()
                                }
                            }
                            .onChange(of: isBookmarkNoteFocused) { _, focused in
                                if focused {
                                    isEditingBookmarkNote = true
                                } else if bookmarkNote.isEmpty {
                                    isEditingBookmarkNote = false
                                }
                            }
                        #endif

                        // Character count when approaching limit
                        if bookmarkNote.count > 900 {
                            HStack {
                                Spacer()
                                Text("\(bookmarkNote.count)/1000")
                                    .font(.caption)
                                    .foregroundStyle(bookmarkNote.count > 1000 ? .red : .secondary)
                                    .monospacedDigit()
                            }
                        }
                    }
                }
            }
        }
    }

    private func infoRow(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(value)
                .font(.subheadline)
                .fontWeight(.medium)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Description Section

    private var descriptionSection: some View {
        CollapsibleSection(title: String(localized: "video.description"), isExpanded: $isDescriptionExpanded) {
            if isLoadingVideoDetails {
                // Loading state
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
                .padding(.vertical, 20)
            } else if let description = displayedVideo?.description, !description.isEmpty {
                // Description available
                Text(DescriptionText.attributed(description, linkColor: accentColor))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .tint(accentColor)
                    .handleTimestampLinks(using: playerService)
                    #if !os(tvOS)
                    .textSelection(.enabled)
                    #endif
            }
        }
    }

    // MARK: - Original Title Section

    private var originalTitleSection: some View {
        CollapsibleSection(title: String(localized: "video.originalTitle"), isExpanded: $isOriginalTitleExpanded) {
            if let title = displayedVideo?.title {
                Text(title)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    #if !os(tvOS)
                    .textSelection(.enabled)
                    #endif
            }
        }
    }

    // MARK: - Related Videos Section

    private func relatedVideosSection(_ videos: [Video]) -> some View {
        #if os(tvOS)
        let rowSpacing: CGFloat = 32
        #else
        let rowSpacing: CGFloat = 12
        #endif
        return CollapsibleSection(title: String(localized: "videoInfo.section.relatedVideos"), isExpanded: $isRelatedExpanded) {
            LazyVStack(spacing: rowSpacing) {
                ForEach(Array(videos.enumerated()), id: \.element.id) { index, relatedVideo in
                    VideoRowView(video: relatedVideo, style: .regular)
                        .tappableVideo(
                            relatedVideo,
                            queueSource: .manual,
                            sourceLabel: String(localized: "videoInfo.section.relatedVideos"),
                            videoList: videos,
                            videoIndex: index,
                            loadMoreVideos: nil
                        )
                        #if !os(tvOS)
                        .videoSwipeActions(video: relatedVideo)
                        #endif

                    #if !os(tvOS)
                    if index < videos.count - 1 {
                        Divider()
                            .padding(.leading, VideoRowStyle.regular.thumbnailWidth + 12)
                    }
                    #endif
                }
            }
        }
    }

    // MARK: - Comments Section

    @ViewBuilder
    private var commentsSection: some View {
        if supportsComments {
            CollapsibleSection(title: String(localized: "videoInfo.section.comments"), isExpanded: $isCommentsExpanded) {
                switch commentsState {
                case .idle, .loading:
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                    .padding(.vertical, 20)

                case .disabled:
                    HStack {
                        Spacer()
                        VStack(spacing: 8) {
                            Image(systemName: "exclamationmark.bubble")
                                .font(.title2)
                                .foregroundStyle(.secondary)
                            Text(String(localized: "videoInfo.comments.disabled"))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 20)

                case .error:
                    HStack {
                        Spacer()
                        VStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle")
                                .font(.title2)
                                .foregroundStyle(.secondary)
                            Text(String(localized: "videoInfo.comments.error"))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 20)

                case .loaded, .loadingMore:
                    if comments.isEmpty {
                        HStack {
                            Spacer()
                            Text(String(localized: "videoInfo.comments.empty"))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Spacer()
                        }
                        .padding(.vertical, 20)
                    } else if let video = displayedVideo {
                        VStack(alignment: .leading, spacing: 0) {
                            // Show first 3 comments as preview
                            ForEach(comments.prefix(3)) { comment in
                                CommentView(
                                    comment: comment,
                                    videoID: video.id.videoID,
                                    source: video.id.source,
                                    isReply: false
                                )
                                .padding(.vertical, 4)
                            }

                            // View All Comments button
                            if comments.count > 3 || commentsContinuation != nil {
                                Button {
                                    showingCommentsSheet = true
                                } label: {
                                    HStack {
                                        Text(String(localized: "videoInfo.viewAllComments"))
                                            .fontWeight(.medium)
                                        Image(systemName: "chevron.right")
                                    }
                                    .font(.subheadline)
                                    #if !os(tvOS)
                                    .foregroundStyle(accentColor)
                                    #endif
                                }
                                .buttonStyle(.plain)
                                #if os(tvOS)
                                .padding(.vertical, 16)
                                #else
                                .padding(.top, 12)
                                #endif
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Comments Sheet

    @ViewBuilder
    private var commentsSheetContent: some View {
        if let video = displayedVideo {
            NavigationStack {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(comments) { comment in
                            CommentView(
                                comment: comment,
                                videoID: video.id.videoID,
                                source: video.id.source,
                                isReply: false
                            )
                            .padding(.horizontal)
                            .padding(.vertical, 4)
                            .onAppear {
                                // Infinite scroll: load more when last comment appears
                                if comment.id == comments.last?.id {
                                    loadMoreComments()
                                }
                            }
                        }

                        // Loading indicator at the bottom
                        if commentsState == .loadingMore {
                            HStack {
                                Spacer()
                                ProgressView()
                                Spacer()
                            }
                            .padding()
                        }
                    }
                }
                #if os(tvOS)
                .background(Color.black.ignoresSafeArea())
                #endif
                .navigationTitle(String(localized: "videoInfo.section.comments"))
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
                #if !os(tvOS)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(role: .cancel) {
                            showingCommentsSheet = false
                        } label: {
                            Label(String(localized: "common.close"), systemImage: "xmark")
                                .labelStyle(.iconOnly)
                        }
                    }
                }
                #endif
            }
        }
    }

    // MARK: - Actions

    private func toggleBookmark() {
        guard let dataManager, let video = displayedVideo else { return }

        if isBookmarked {
            // Already bookmarked - show confirmation to remove
            showingRemoveBookmarkAlert = true
        } else {
            // Not bookmarked - add bookmark
            dataManager.addBookmark(for: video)
            isBookmarked = true
            
            // Fetch newly created bookmark and load its data
            if let bookmark = dataManager.bookmark(for: video.id.videoID) {
                currentBookmark = bookmark
                bookmarkTags = bookmark.tags
                bookmarkNote = bookmark.note ?? ""
            }
        }
    }
    
    private func removeBookmark() {
        guard let dataManager, let video = displayedVideo else { return }
        
        // Cancel any pending save
        bookmarkSaveTask?.cancel()
        
        // Remove bookmark
        dataManager.removeBookmark(for: video.id.videoID)
        isBookmarked = false
        currentBookmark = nil
        bookmarkTags = []
        bookmarkNote = ""
    }
    
    private func debouncedSaveBookmark() {
        // Cancel existing save task
        bookmarkSaveTask?.cancel()
        
        // Create new debounced save task
        bookmarkSaveTask = Task {
            // Wait 1 second before saving
            try? await Task.sleep(for: .seconds(1))
            
            // Check if task was cancelled
            guard !Task.isCancelled else { return }
            
            // Save bookmark
            await MainActor.run {
                saveBookmark()
            }
        }
    }
    
    private func saveBookmark() {
        guard let dataManager, let video = displayedVideo else { return }
        
        // Truncate note if too long
        let finalNote = bookmarkNote.trimmingCharacters(in: .whitespacesAndNewlines)
        let truncatedNote = String(finalNote.prefix(1000))
        
        // Update bookmark
        dataManager.updateBookmark(
            videoID: video.id.videoID,
            tags: bookmarkTags,
            note: truncatedNote.isEmpty ? nil : truncatedNote
        )
        
        // Refresh bookmark data
        currentBookmark = dataManager.bookmark(for: video.id.videoID)
    }

    private func loadComments() {
        // Don't load comments for non-YouTube sources
        guard supportsComments else { return }
        guard commentsState == .idle else { return }
        guard let video = displayedVideo,
              let contentService, let instancesManager,
              let instance = instancesManager.instance(for: video) else {
            commentsState = .error
            return
        }

        commentsState = .loading

        Task {
            do {
                let page = try await contentService.comments(
                    videoID: video.id.videoID,
                    instance: instance,
                    continuation: nil
                )
                await MainActor.run {
                    comments = page.comments
                    commentsContinuation = page.continuation
                    commentsState = .loaded
                }
            } catch let error as APIError where error == .commentsDisabled {
                await MainActor.run {
                    commentsState = .disabled
                }
            } catch {
                await MainActor.run {
                    commentsState = .error
                }
            }
        }
    }

    private func loadMoreComments() {
        guard commentsState != .loadingMore else { return }
        guard let continuation = commentsContinuation else { return }
        guard let video = displayedVideo,
              let contentService, let instancesManager,
              let instance = instancesManager.instance(for: video) else { return }

        commentsState = .loadingMore

        Task {
            do {
                let page = try await contentService.comments(
                    videoID: video.id.videoID,
                    instance: instance,
                    continuation: continuation
                )
                await MainActor.run {
                    comments.append(contentsOf: page.comments)
                    commentsContinuation = page.continuation
                    commentsState = .loaded
                }
            } catch {
                await MainActor.run {
                    commentsState = .loaded // Don't show error on load more failure
                }
            }
        }
    }
    
    // MARK: - Video Details Loading
    
    /// Load full video details from the API (fails silently)
    @MainActor
    private func loadVideoDetails() async {
        guard let base = baseVideo else {
            isLoadingVideoDetails = false
            return
        }
        let videoID = base.id.videoID
        
        // Skip if already loaded
        guard loadedVideoDetails[videoID] == nil else {
            isLoadingVideoDetails = false
            return
        }

        // Check the video source type for extracted content
        if case .extracted(let extractor, let originalURL) = base.id.source {
            // Skip API fetch for local media sources (SMB, WebDAV, local files)
            if extractor == MediaFile.smbProvider
                || extractor == MediaFile.webdavProvider
                || extractor == MediaFile.localFolderProvider {
                isLoadingVideoDetails = false
                return
            }

            // For other extracted content (Bilibili, etc.), use the extract endpoint
            guard let contentService,
                  let instancesManager,
                  let instance = instancesManager.yatteeServerInstances.first else {
                isLoadingVideoDetails = false
                return
            }

            isLoadingVideoDetails = true
            do {
                // Use extractURL method - just use the video part
                let (fullVideo, _, _) = try await contentService.extractURL(originalURL, instance: instance)
                loadedVideoDetails[videoID] = fullVideo
                CachedChannelData.cacheAuthor(fullVideo.author)
            } catch {
                // Fail silently - use partial video data we have
            }
            isLoadingVideoDetails = false
            return
        }

        // For YouTube/global content, use existing video endpoint
        guard let contentService,
              let instancesManager,
              let instance = instancesManager.instance(for: base) else {
            isLoadingVideoDetails = false
            return
        }

        isLoadingVideoDetails = true

        do {
            let fullVideo = try await contentService.video(
                id: videoID,
                instance: instance
            )
            loadedVideoDetails[videoID] = fullVideo
            CachedChannelData.cacheAuthor(fullVideo.author)
        } catch {
            // Fail silently - just use the partial video data we have
        }

        isLoadingVideoDetails = false
    }
    
    /// Load initial video from API (for videoID init mode).
    private func loadInitialVideoIfNeeded() async {
        guard case .videoID(let videoID) = initMode else { return }

        guard let contentService,
              let instancesManager,
              let instance = instancesManager.instance(for: videoID.source) else {
            initialVideoLoadError = String(localized: "error.noInstance")
            return
        }
        
        isLoadingInitialVideo = true
        initialVideoLoadError = nil
        
        do {
            loadedVideo = try await contentService.video(id: videoID.videoID, instance: instance)
            isLoadingInitialVideo = false
            
            // Now that video is loaded, trigger initial data loading
            #if !os(tvOS)
            loadVideoData()
            #else
            if let video = displayedVideo {
                isBookmarked = dataManager?.isBookmarked(videoID: video.id.videoID) ?? false
                watchEntry = dataManager?.watchEntry(for: video.id.videoID)
            }
            loadComments()
            #endif
        } catch {
            initialVideoLoadError = error.localizedDescription
            isLoadingInitialVideo = false
        }
    }
    
    // MARK: - Queue Context Helpers

    /// Play the video, respecting the user's resume action setting for partially watched videos.
    private func playVideo() {
        guard let video = displayedVideo, let env = appEnvironment else { return }
        
        // Get saved watch progress from database
        let savedProgress = env.dataManager.watchProgress(for: video.id.videoID)
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
                // Show the resume action sheet
                resumeSheetData = ResumeSheetData(video: video, resumeTime: savedProgress)
            }
        } else {
            // No saved progress or video was completed - play from beginning
            playVideoWithStartTime(0)
        }
    }
    
    /// Plays the video with the specified start time.
    private func playVideoWithStartTime(_ time: TimeInterval) {
        guard let video = displayedVideo else { return }

        // Media-browser playback must go through `playFromMediaBrowser` so the
        // queue manager sets up on-demand stream/caption resolution — otherwise
        // Samba/WebDAV files cannot play.
        if let ctx = videoQueueContext,
           let mb = ctx.mediaBrowserPlayback,
           let queueManager = queueManager {
            let playableFiles = mb.allFilesInFolder.filter { $0.isPlayable }
            let index = playableFiles.firstIndex(where: { $0.toVideo().id.videoID == video.id.videoID })
                ?? currentVideoIndex
                ?? ctx.videoIndex
                ?? 0
            queueManager.playFromMediaBrowser(
                files: playableFiles,
                index: index,
                source: mb.source,
                allFilesInFolder: mb.allFilesInFolder
            )
            return
        }

        guard let context = videoQueueContext,
              context.hasQueueInfo,
              let queueManager = queueManager,
              let list = context.videoList else {
            // No queue context - play single video
            if time > 0 {
                playerService?.openVideo(video, startTime: time)
            } else {
                playerService?.openVideo(video)
            }
            return
        }
        
        // Use current index if navigating, otherwise use original context index
        let playIndex = currentVideoIndex ?? context.videoIndex ?? 0
        
        // Play with queue context
        queueManager.playFromList(
            videos: list,
            index: playIndex,
            queueSource: context.queueSource,
            sourceLabel: context.sourceLabel,
            startTime: time
        )
    }
    
    // MARK: - Video Navigation
    
    #if !os(tvOS)
    /// Whether we can navigate to the previous video
    private var canNavigatePrevious: Bool {
        guard let index = currentVideoIndex else { return false }
        return index > 0
    }
    
    /// Whether we can navigate to the next video
    private var canNavigateNext: Bool {
        guard let index = currentVideoIndex else {
            return false
        }
        
        // Check if we can navigate within loaded videos
        if let videos = allVideos, index < videos.count - 1 {
            return true
        }
        
        // Check if we can load more videos
        return videoQueueContext?.canLoadMore == true
    }
    
    /// Whether we should pre-load more videos (at 95% of current list)
    private var shouldPreloadMore: Bool {
        guard let videos = allVideos,
              let index = currentVideoIndex,
              videoQueueContext?.canLoadMore == true,
              !isLoadingMoreVideos,
              loadMoreError == nil else {
            return false
        }
        
        let threshold = Int(Double(videos.count) * 0.95)
        return index >= threshold
    }
    
    /// Navigate to the previous video in the queue
    private func navigateToPrevious() {
        guard canNavigatePrevious, let index = currentVideoIndex else { return }
        currentVideoIndex = index - 1
    }
    
    /// Navigate to the next video in the queue
    private func navigateToNext() {
        guard let index = currentVideoIndex else {
            return
        }
        
        // Clear any previous errors when navigating
        loadMoreError = nil
        
        // If we're at the last loaded video and can load more, trigger loading
        if let videos = allVideos,
           index == videos.count - 1,
           videoQueueContext?.canLoadMore == true {
            Task {
                await loadMoreVideos()
                // After loading, navigate to next video if available
                if let newVideos = allVideos, index < newVideos.count - 1 {
                    await MainActor.run {
                        currentVideoIndex = index + 1
                    }
                }
            }
        } else if canNavigateNext {
            // Normal navigation within loaded videos
            currentVideoIndex = index + 1
        }
    }
    
    /// Load more videos via continuation callback
    @MainActor
    private func loadMoreVideos() async {
        guard !isLoadingMoreVideos,
              let callback = videoQueueContext?.loadMoreVideos else {
            return
        }
        
        isLoadingMoreVideos = true
        loadMoreError = nil
        
        do {
            let (newVideos, _) = try await callback()
            
            // Limit extended list to 500 videos to prevent memory issues
            let remainingCapacity = max(0, 500 - extendedVideoList.count)
            let videosToAdd = Array(newVideos.prefix(remainingCapacity))
            
            extendedVideoList.append(contentsOf: videosToAdd)
        } catch {
            loadMoreError = error.localizedDescription
        }
        
        isLoadingMoreVideos = false
    }
    
    /// Load video-specific data (bookmark, watch history, comments, etc.)
    private func loadVideoData() {
        guard let video = displayedVideo else { return }
        
        isBookmarked = dataManager?.isBookmarked(videoID: video.id.videoID) ?? false
        
        // Load bookmark details if bookmarked
        if isBookmarked, let bookmark = dataManager?.bookmark(for: video.id.videoID) {
            currentBookmark = bookmark
            bookmarkTags = bookmark.tags
            bookmarkNote = bookmark.note ?? ""
        } else {
            currentBookmark = nil
            bookmarkTags = []
            bookmarkNote = ""
        }
        
        watchEntry = dataManager?.watchEntry(for: video.id.videoID)
        #if !os(tvOS)
        download = downloadManager?.download(for: video.id)
        #endif
        loadComments()
    }
    
    #if os(macOS)
    /// Navigation buttons overlay - floats at bottom of screen (macOS only)
    @ViewBuilder
    private var navigationButtonsOverlay: some View {
        VStack {
            Spacer()
            
            HStack {
                // Previous button
                if canNavigatePrevious {
                    VideoNavigationButton(direction: .previous) {
                        navigateToPrevious()
                    }
                    .transition(.opacity.combined(with: .scale))
                }
                
                Spacer(minLength: 0)
                
                // Next button
                if canNavigateNext {
                    VideoNavigationButton(
                        direction: .next,
                        action: navigateToNext,
                        isLoading: isLoadingMoreVideos,
                        hasError: loadMoreError != nil
                    )
                    .transition(.opacity.combined(with: .scale))
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
            .contentShape(Rectangle())
        }
        .animation(.easeInOut(duration: 0.2), value: canNavigatePrevious)
        .animation(.easeInOut(duration: 0.2), value: canNavigateNext)
    }
    #endif
    #endif
}

// MARK: - Collapsible Section

/// A collapsible section with animated expand/collapse behavior.
private struct CollapsibleSection<Content: View>: View {
    let title: String
    @Binding var isExpanded: Bool
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header button
            Button {
                withAnimation(.easeInOut(duration: 0.25)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack {
                    Text(title)
                        .font(.headline)

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding()

            // Content
            if isExpanded {
                content()
                    .padding(.horizontal)
                    .padding(.bottom)
                    .transition(.opacity)
            }
        }
    }
}

// MARK: - Scroll Offset Modifier

private struct VideoInfoScrollOffsetModifier: ViewModifier {
    @Binding var scrollOffset: CGFloat

    func body(content: Content) -> some View {
        content
            .onScrollGeometryChange(for: CGFloat.self) { geometry in
                geometry.contentOffset.y
            } action: { _, newValue in
                if scrollOffset != newValue {
                    scrollOffset = newValue
                }
            }
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        VideoInfoView(video: .preview)
            .videoQueueContext(.init(video: .preview, queueSource: .manual, sourceLabel: "Manual", videoList: [.preview, .livePreview], videoIndex: 0, startTime: 0, loadMoreVideos: .none))
    }
}
