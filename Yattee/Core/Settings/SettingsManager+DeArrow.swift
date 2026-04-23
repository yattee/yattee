//
//  SettingsManager+DeArrow.swift
//  Yattee
//
//  DeArrow and Return YouTube Dislike settings.
//

import Foundation

extension SettingsManager {
    // MARK: - Return YouTube Dislike Settings

    /// Whether Return YouTube Dislike is enabled. Default is false.
    var returnYouTubeDislikeEnabled: Bool {
        get {
            if let cached = _returnYouTubeDislikeEnabled { return cached }
            return bool(for: .returnYouTubeDislikeEnabled, default: false)
        }
        set {
            _returnYouTubeDislikeEnabled = newValue
            set(newValue, for: .returnYouTubeDislikeEnabled)
        }
    }

    // MARK: - DeArrow Settings

    /// The DeArrow API URL. Defaults to the official instance.
    static let defaultDeArrowAPIURL = "https://sponsor.ajay.app"

    /// The DeArrow thumbnail generation service URL. Defaults to the official instance.
    static let defaultDeArrowThumbnailAPIURL = "https://dearrow-thumb.ajay.app"

    /// Whether DeArrow is enabled. Default is false.
    var deArrowEnabled: Bool {
        get {
            if let cached = _deArrowEnabled { return cached }
            return bool(for: .deArrowEnabled, default: false)
        }
        set {
            _deArrowEnabled = newValue
            set(newValue, for: .deArrowEnabled)
        }
    }

    /// Whether DeArrow should replace video titles. Default is true when DeArrow is enabled.
    var deArrowReplaceTitles: Bool {
        get {
            if let cached = _deArrowReplaceTitles { return cached }
            return bool(for: .deArrowReplaceTitles, default: true)
        }
        set {
            _deArrowReplaceTitles = newValue
            set(newValue, for: .deArrowReplaceTitles)
        }
    }

    /// Whether DeArrow should replace video thumbnails. Default is true when DeArrow is enabled.
    var deArrowReplaceThumbnails: Bool {
        get {
            if let cached = _deArrowReplaceThumbnails { return cached }
            return bool(for: .deArrowReplaceThumbnails, default: true)
        }
        set {
            _deArrowReplaceThumbnails = newValue
            set(newValue, for: .deArrowReplaceThumbnails)
        }
    }

    var deArrowAPIURL: String {
        get {
            if let cached = _deArrowAPIURL { return cached }
            return string(for: .deArrowAPIURL) ?? Self.defaultDeArrowAPIURL
        }
        set {
            _deArrowAPIURL = newValue
            set(newValue, for: .deArrowAPIURL)
        }
    }

    var deArrowThumbnailAPIURL: String {
        get {
            if let cached = _deArrowThumbnailAPIURL { return cached }
            return string(for: .deArrowThumbnailAPIURL) ?? Self.defaultDeArrowThumbnailAPIURL
        }
        set {
            _deArrowThumbnailAPIURL = newValue
            set(newValue, for: .deArrowThumbnailAPIURL)
        }
    }

    // MARK: - Short Link Resolution

    /// When enabled, taps on known URL shorteners (bit.ly, tinyurl, t.co, …) in
    /// descriptions and comments follow the redirect and, if the destination is a
    /// supported YouTube/PeerTube URL, open it in-app. Off by default because it
    /// performs a network request to the shortener host on tap.
    var resolveShortLinksEnabled: Bool {
        get {
            if let cached = _resolveShortLinksEnabled { return cached }
            return bool(for: .resolveShortLinksEnabled, default: false)
        }
        set {
            _resolveShortLinksEnabled = newValue
            set(newValue, for: .resolveShortLinksEnabled)
        }
    }
}
