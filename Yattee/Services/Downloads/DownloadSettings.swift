//
//  DownloadSettings.swift
//  Yattee
//
//  Local-only settings for downloads sorting and grouping.
//  These settings are NOT synced to iCloud.
//

import Foundation

/// Sort options for completed downloads.
enum DownloadSortOption: String, CaseIterable, Codable {
    case name
    case downloadDate
    case fileSize

    var displayName: String {
        switch self {
        case .name:
            return String(localized: "downloads.sort.name")
        case .downloadDate:
            return String(localized: "downloads.sort.downloadDate")
        case .fileSize:
            return String(localized: "downloads.sort.fileSize")
        }
    }

    var systemImage: String {
        switch self {
        case .name:
            return "textformat"
        case .downloadDate:
            return "calendar"
        case .fileSize:
            return "internaldrive"
        }
    }
}

/// Sort direction.
enum SortDirection: String, CaseIterable, Codable {
    case ascending
    case descending

    var systemImage: String {
        switch self {
        case .ascending:
            return "arrow.up"
        case .descending:
            return "arrow.down"
        }
    }

    mutating func toggle() {
        self = self == .ascending ? .descending : .ascending
    }
}

/// Manages download view settings locally (not synced to iCloud).
@MainActor
@Observable
final class DownloadSettings {
    // MARK: - Storage Keys

    private enum Keys {
        static let sortOption = "downloads.sortOption"
        static let sortDirection = "downloads.sortDirection"
        static let groupByChannel = "downloads.groupByChannel"
        static let allowCellularDownloads = "downloads.allowCellularDownloads"
        static let preferredQuality = "downloads.preferredQuality"
        static let includeSubtitlesInAutoDownload = "downloads.includeSubtitlesInAutoDownload"
        static let maxConcurrentDownloads = "downloads.maxConcurrentDownloads"
    }

    // MARK: - Storage

    private let defaults = UserDefaults.standard

    // MARK: - Cached Values

    private var _sortOption: DownloadSortOption?
    private var _sortDirection: SortDirection?
    private var _groupByChannel: Bool?
    private var _allowCellularDownloads: Bool?
    private var _preferredDownloadQuality: DownloadQuality?
    private var _includeSubtitlesInAutoDownload: Bool?
    private var _maxConcurrentDownloads: Int?

    // MARK: - Properties

    /// The current sort option for completed downloads.
    var sortOption: DownloadSortOption {
        get {
            if let cached = _sortOption { return cached }
            guard let rawValue = defaults.string(forKey: Keys.sortOption),
                  let option = DownloadSortOption(rawValue: rawValue) else {
                return .downloadDate
            }
            return option
        }
        set {
            _sortOption = newValue
            defaults.set(newValue.rawValue, forKey: Keys.sortOption)
        }
    }

    /// The current sort direction.
    var sortDirection: SortDirection {
        get {
            if let cached = _sortDirection { return cached }
            guard let rawValue = defaults.string(forKey: Keys.sortDirection),
                  let direction = SortDirection(rawValue: rawValue) else {
                return .descending
            }
            return direction
        }
        set {
            _sortDirection = newValue
            defaults.set(newValue.rawValue, forKey: Keys.sortDirection)
        }
    }

    /// Whether to group downloads by channel.
    var groupByChannel: Bool {
        get {
            if let cached = _groupByChannel { return cached }
            return defaults.bool(forKey: Keys.groupByChannel)
        }
        set {
            _groupByChannel = newValue
            defaults.set(newValue, forKey: Keys.groupByChannel)
        }
    }

    #if os(iOS)
    /// Whether to allow downloads on cellular network. Default is false (WiFi only).
    var allowCellularDownloads: Bool {
        get {
            if let cached = _allowCellularDownloads { return cached }
            return defaults.bool(forKey: Keys.allowCellularDownloads)
        }
        set {
            _allowCellularDownloads = newValue
            defaults.set(newValue, forKey: Keys.allowCellularDownloads)
        }
    }
    #endif

    /// Preferred download quality. When set to anything other than .ask,
    /// downloads will start automatically without showing the stream selection sheet.
    var preferredDownloadQuality: DownloadQuality {
        get {
            if let cached = _preferredDownloadQuality { return cached }
            guard let rawValue = defaults.string(forKey: Keys.preferredQuality),
                  let quality = DownloadQuality(rawValue: rawValue) else {
                return .hd1080p
            }
            return quality
        }
        set {
            _preferredDownloadQuality = newValue
            defaults.set(newValue.rawValue, forKey: Keys.preferredQuality)
        }
    }

    /// Whether to include subtitles when auto-downloading (non-Ask mode).
    /// Uses the preferred subtitle language from playback settings.
    var includeSubtitlesInAutoDownload: Bool {
        get {
            if let cached = _includeSubtitlesInAutoDownload { return cached }
            return defaults.bool(forKey: Keys.includeSubtitlesInAutoDownload)
        }
        set {
            _includeSubtitlesInAutoDownload = newValue
            defaults.set(newValue, forKey: Keys.includeSubtitlesInAutoDownload)
        }
    }

    /// Maximum number of concurrent downloads. Default is 2.
    var maxConcurrentDownloads: Int {
        get {
            if let cached = _maxConcurrentDownloads { return cached }
            let value = defaults.integer(forKey: Keys.maxConcurrentDownloads)
            return value > 0 ? value : 2
        }
        set {
            _maxConcurrentDownloads = newValue
            defaults.set(newValue, forKey: Keys.maxConcurrentDownloads)
        }
    }

    // MARK: - Sorting

    /// Sorts an array of downloads based on current settings.
    func sorted(_ downloads: [Download]) -> [Download] {
        let sorted = downloads.sorted { first, second in
            let comparison: Bool
            switch sortOption {
            case .name:
                comparison = first.title.localizedCaseInsensitiveCompare(second.title) == .orderedAscending
            case .downloadDate:
                let firstDate = first.completedAt ?? first.startedAt ?? Date.distantPast
                let secondDate = second.completedAt ?? second.startedAt ?? Date.distantPast
                comparison = firstDate < secondDate
            case .fileSize:
                comparison = first.totalBytes < second.totalBytes
            }

            return sortDirection == .ascending ? comparison : !comparison
        }
        return sorted
    }

    /// Groups downloads by channel.
    func groupedByChannel(_ downloads: [Download]) -> [(channel: String, channelID: String, downloads: [Download])] {
        let grouped = Dictionary(grouping: downloads) { $0.channelID }

        return grouped.map { (channelID, channelDownloads) in
            let channelName = channelDownloads.first?.channelName ?? channelID
            return (channel: channelName, channelID: channelID, downloads: sorted(channelDownloads))
        }
        .sorted { $0.channel.localizedCaseInsensitiveCompare($1.channel) == .orderedAscending }
    }
}
