//
//  DownloadTypes.swift
//  Yattee
//
//  Type definitions for downloads.
//

import Foundation

/// Download priority levels.
enum DownloadPriority: Int, Codable, Sendable {
    case low = 0
    case normal = 1
    case high = 2
}

/// Download status.
enum DownloadStatus: String, Codable, Sendable {
    case queued
    case downloading
    case paused
    case completed
    case failed
}

/// Download phase for multi-file downloads (video + audio + caption + storyboard + thumbnail).
enum DownloadPhase: String, Codable, Sendable {
    case video      // Downloading video file
    case audio      // Downloading audio file (for video-only streams)
    case caption    // Downloading caption file
    case storyboard // Downloading storyboard sprite sheets
    case thumbnail  // Downloading video and channel thumbnails for offline artwork
    case complete   // All files downloaded
}
