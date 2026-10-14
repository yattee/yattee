//
//  VideoQueueContext.swift
//  Yattee
//
//  Context information for video queue when navigating to video details.
//

import Foundation

/// Closure type for loading more videos via continuation
typealias LoadMoreVideosCallback = @Sendable () async throws -> ([Video], String?)

/// Extra payload required to play files from a media source (WebDAV/SMB/local folder)
/// via `QueueManager.playFromMediaBrowser`. Without this, playback falls back to
/// `openVideo` / `playFromList`, which do not set up on-demand stream and caption
/// resolution for media-browser files.
struct MediaBrowserPlaybackInfo: Equatable, Hashable {
    let source: MediaSource
    let allFilesInFolder: [MediaFile]
}

/// Where a video info page has got to in its queue. A layout swap (tab bar ↔
/// split view sidebar) rebuilds the page from its path entry, so this lives on
/// the entry's context rather than in the page's view state.
/// `NavigationRouter.push` gives every pushed page its own instance.
final class VideoInfoPageState {
    var currentVideoIndex: Int?
    /// Videos appended through continuation loading, past the original list.
    var extendedVideoList: [Video] = []
}

/// Context information for playing a video with queue support.
/// Used when navigating from list views (subscriptions, search, etc.) to video info pages.
struct VideoQueueContext {
    /// The video being viewed
    let video: Video

    /// Queue source for continuation loading
    let queueSource: QueueSource?

    /// Display label for the queue source (e.g., "Subscriptions", "Search Results")
    let sourceLabel: String?

    /// All videos in the current list
    let videoList: [Video]?

    /// Index of the current video in the list
    let videoIndex: Int?

    /// Optional start time in seconds
    let startTime: TimeInterval?

    /// Callback to load more videos when reaching the end of the current list
    /// Returns new videos and updated continuation token
    let loadMoreVideos: LoadMoreVideosCallback?

    /// When set, playback from VideoInfoView must route through
    /// `QueueManager.playFromMediaBrowser` using this payload.
    var mediaBrowserPlayback: MediaBrowserPlaybackInfo? = nil

    /// Position requested by an opened timed link (`?t=`). Unlike `startTime`
    /// (a resume position), it is honored as-is and skips the resume prompt.
    var linkStartTime: TimeInterval? = nil

    /// Page position kept across rebuilds; ignored by equality and hashing.
    var pageState = VideoInfoPageState()
    
    /// Whether this context has valid queue information
    var hasQueueInfo: Bool {
        videoList != nil && videoIndex != nil
    }
    
    /// Whether more videos can be loaded via continuation
    var canLoadMore: Bool {
        let hasCallback = loadMoreVideos != nil
        let supportsContinuation = queueSource?.supportsContinuation == true
        return hasCallback && supportsContinuation
    }
    
    /// Creates a minimal context with just the video (no queue)
    static func single(_ video: Video, startTime: TimeInterval? = nil) -> VideoQueueContext {
        VideoQueueContext(
            video: video,
            queueSource: nil,
            sourceLabel: nil,
            videoList: nil,
            videoIndex: nil,
            startTime: startTime,
            loadMoreVideos: nil
        )
    }
}

// MARK: - Equatable & Hashable
// Note: Excludes loadMoreVideos callback since closures aren't equatable

extension VideoQueueContext: Equatable {
    static func == (lhs: VideoQueueContext, rhs: VideoQueueContext) -> Bool {
        lhs.video == rhs.video &&
        lhs.queueSource == rhs.queueSource &&
        lhs.sourceLabel == rhs.sourceLabel &&
        lhs.videoList == rhs.videoList &&
        lhs.videoIndex == rhs.videoIndex &&
        lhs.startTime == rhs.startTime &&
        lhs.mediaBrowserPlayback == rhs.mediaBrowserPlayback &&
        lhs.linkStartTime == rhs.linkStartTime
    }
}

extension VideoQueueContext: Hashable {
    func hash(into hasher: inout Hasher) {
        hasher.combine(video)
        hasher.combine(queueSource)
        hasher.combine(sourceLabel)
        hasher.combine(videoList)
        hasher.combine(videoIndex)
        hasher.combine(startTime)
        hasher.combine(mediaBrowserPlayback)
        hasher.combine(linkStartTime)
    }
}
