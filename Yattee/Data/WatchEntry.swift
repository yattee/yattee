//
//  WatchEntry.swift
//  Yattee
//
//  SwiftData model for tracking video watch history.
//

import Foundation
import SwiftData

/// Represents a watched video entry in the user's history.
@Model
final class WatchEntry {
    // MARK: - Video Identity

    /// The video ID string (YouTube ID or PeerTube UUID).
    var videoID: String = ""

    /// The content source raw value for encoding ("global", "federated", "extracted").
    var sourceRawValue: String = "global"

    /// For global sources: the provider name (e.g., "youtube", "dailymotion").
    var globalProvider: String?

    /// For PeerTube: the instance URL string.
    var instanceURLString: String?

    /// For PeerTube: the UUID.
    var peertubeUUID: String?

    /// For external sources: the extractor name (e.g., "vimeo", "twitter").
    var externalExtractor: String?

    /// For external sources: the original URL for re-extraction.
    var externalURLString: String?

    // MARK: - Video Metadata (cached for offline display)

    /// The video title at time of watching.
    var title: String = ""

    /// The channel/author name.
    var authorName: String = ""

    /// The channel/author ID.
    var authorID: String = ""

    /// Video duration in seconds.
    var duration: TimeInterval = 0

    /// Thumbnail URL string.
    var thumbnailURLString: String?

    // MARK: - Watch Progress

    /// Last watched position in seconds.
    var watchedSeconds: TimeInterval = 0

    /// Whether the video has been fully watched (>90% or manually marked).
    var isFinished: Bool = false

    /// When the video was marked as finished.
    var finishedAt: Date?

    // MARK: - Timestamps

    /// When this entry was first created.
    var createdAt: Date = Date()

    /// When this entry was last updated.
    var updatedAt: Date = Date()

    // MARK: - Initialization

    init(
        videoID: String,
        sourceRawValue: String,
        globalProvider: String? = nil,
        instanceURLString: String? = nil,
        peertubeUUID: String? = nil,
        externalExtractor: String? = nil,
        externalURLString: String? = nil,
        title: String,
        authorName: String,
        authorID: String,
        duration: TimeInterval,
        thumbnailURLString: String? = nil,
        watchedSeconds: TimeInterval = 0,
        isFinished: Bool = false
    ) {
        self.videoID = videoID
        self.sourceRawValue = sourceRawValue
        self.globalProvider = globalProvider
        self.instanceURLString = instanceURLString
        self.peertubeUUID = peertubeUUID
        self.externalExtractor = externalExtractor
        self.externalURLString = externalURLString
        self.title = title
        self.authorName = authorName
        self.authorID = authorID
        self.duration = duration
        self.thumbnailURLString = thumbnailURLString
        self.watchedSeconds = watchedSeconds
        self.isFinished = isFinished
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    // MARK: - Computed Properties

    /// The content source for this entry.
    var contentSource: ContentSource {
        if sourceRawValue == "global" {
            return .global(provider: globalProvider ?? ContentSource.youtubeProvider)
        } else if sourceRawValue == "federated",
                  let urlString = instanceURLString,
                  let url = URL(string: urlString) {
            return .federated(provider: ContentSource.peertubeProvider, instance: url)
        } else if sourceRawValue == "extracted",
                  let extractor = externalExtractor,
                  let urlString = externalURLString,
                  let url = URL(string: urlString) {
            return .extracted(extractor: extractor, originalURL: url)
        }
        return .global(provider: globalProvider ?? ContentSource.youtubeProvider)
    }

    /// The full VideoID for this entry, matching what VideoRowView uses for zoom transitions.
    var videoIdentifier: VideoID {
        VideoID(source: contentSource, videoID: videoID, uuid: peertubeUUID)
    }

    /// The thumbnail URL if available.
    var thumbnailURL: URL? {
        thumbnailURLString.flatMap { URL(string: $0) }
    }

    /// Watch progress as a percentage (0.0 to 1.0).
    var progress: Double {
        guard duration > 0 else { return 0 }
        return min(watchedSeconds / duration, 1.0)
    }

    /// Formatted total duration.
    var formattedDuration: String {
        guard duration > 0 else { return "" }
        let hours = Int(duration) / 3600
        let minutes = (Int(duration) % 3600) / 60
        let seconds = Int(duration) % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%d:%02d", minutes, seconds)
        }
    }

    /// Formatted remaining time.
    var remainingTime: String {
        let remaining = max(0, duration - watchedSeconds)
        let hours = Int(remaining) / 3600
        let minutes = (Int(remaining) % 3600) / 60
        let seconds = Int(remaining) % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%d:%02d", minutes, seconds)
        }
    }

    // MARK: - Methods

    /// Updates the watch progress.
    func updateProgress(seconds: TimeInterval, duration: TimeInterval? = nil) {
        watchedSeconds = seconds
        updatedAt = Date()

        // Update duration if it was 0 and a valid duration is now known
        if self.duration == 0, let newDuration = duration, newDuration > 0 {
            self.duration = newDuration
        }

        // Mark as finished if watched more than 90%
        if progress >= 0.9 && !isFinished {
            isFinished = true
            finishedAt = Date()
        }
    }

    /// Marks the video as finished.
    func markAsFinished() {
        isFinished = true
        finishedAt = Date()
        updatedAt = Date()
    }

    /// Resets the watch progress.
    func resetProgress() {
        watchedSeconds = 0
        isFinished = false
        finishedAt = nil
        updatedAt = Date()
    }
}

// MARK: - Conversion Methods

extension WatchEntry {
    /// Converts this WatchEntry back to a Video model for playback or display.
    func toVideo() -> Video {
        Video(
            id: VideoID(source: contentSource, videoID: videoID),
            title: title,
            description: nil,
            author: Author(id: authorID, name: authorName),
            duration: duration,
            publishedAt: nil,
            publishedText: nil,
            viewCount: nil,
            likeCount: nil,
            thumbnails: thumbnailURL.map { [Thumbnail(url: $0, quality: .medium)] } ?? [],
            isLive: false,
            isUpcoming: false,
            scheduledStartTime: nil
        )
    }

    /// Creates a WatchEntry from a Video model.
    static func from(video: Video) -> WatchEntry {
        let sourceRaw: String
        var provider: String?
        var instanceURL: String?
        var uuid: String?
        var extractor: String?
        var externalURL: String?

        switch video.id.source {
        case .global(let prov):
            sourceRaw = "global"
            provider = prov
        case .federated(_, let instance):
            sourceRaw = "federated"
            instanceURL = instance.absoluteString
            uuid = video.id.uuid
        case .extracted(let ext, let originalURL):
            sourceRaw = "extracted"
            extractor = ext
            externalURL = originalURL.absoluteString
        }

        return WatchEntry(
            videoID: video.id.videoID,
            sourceRawValue: sourceRaw,
            globalProvider: provider,
            instanceURLString: instanceURL,
            peertubeUUID: uuid,
            externalExtractor: extractor,
            externalURLString: externalURL,
            title: video.title,
            authorName: video.author.name,
            authorID: video.author.id,
            duration: video.duration,
            thumbnailURLString: video.bestThumbnail?.url.absoluteString
        )
    }
}
