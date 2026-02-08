//
//  VideoQueueContext.swift
//  Yattee
//
//  Context information for video queue when navigating to video details.
//

import Foundation

/// Closure type for loading more videos via continuation
typealias LoadMoreVideosCallback = @Sendable () async throws -> ([Video], String?)

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
    
    /// Whether this context has valid queue information
    var hasQueueInfo: Bool {
        videoList != nil && videoIndex != nil
    }
    
    /// Number of videos that will be queued after the current one
    var remainingVideosCount: Int {
        guard let list = videoList, let index = videoIndex else { return 0 }
        return max(0, list.count - index - 1)
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
        lhs.startTime == rhs.startTime
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
    }
}
