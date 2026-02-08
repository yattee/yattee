//
//  SidebarManager.swift
//  Yattee
//
//  Manages sidebar content by loading user data (subscriptions, playlists)
//  and generating sidebar items for the TabSection-based navigation.
//

import Foundation
import Combine

/// Manages sidebar state and content generation.
@Observable @MainActor
final class SidebarManager {
    // MARK: - Published Items

    /// Channel items for the Channels section.
    private(set) var channelItems: [SidebarItem] = []

    /// Playlist items for the Collections section.
    private(set) var playlistItems: [SidebarItem] = []

    /// Media source items for the Media Sources section.
    private(set) var mediaSourceItems: [SidebarItem] = []

    /// Instance items for the Sources section.
    private(set) var instanceItems: [SidebarItem] = []

    /// All source items (instances + media sources) combined and sorted.
    /// This is the primary property to use for displaying sources in a unified list.
    private(set) var sortedSourceItems: [SidebarItem] = []

    /// Whether there are no source items at all.
    var hasNoSources: Bool {
        instanceItems.isEmpty && mediaSourceItems.isEmpty
    }

    // MARK: - Dependencies

    private weak var dataManager: DataManager?
    private weak var settingsManager: SettingsManager?
    private weak var mediaSourcesManager: MediaSourcesManager?
    private weak var instancesManager: InstancesManager?
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Cached Data (to avoid repeated DB queries during layout)
    
    private var cachedSubscriptions: [Subscription] = []
    private var cachedPlaylists: [LocalPlaylist] = []

    // MARK: - Initialization

    init() {
        setupNotificationObservers()
    }

    /// Configure the manager with dependencies.
    func configure(
        dataManager: DataManager,
        settingsManager: SettingsManager,
        mediaSourcesManager: MediaSourcesManager? = nil,
        instancesManager: InstancesManager? = nil
    ) {
        self.dataManager = dataManager
        self.settingsManager = settingsManager
        self.mediaSourcesManager = mediaSourcesManager
        self.instancesManager = instancesManager
        loadData()
    }

    // MARK: - Data Loading

    /// Loads subscriptions, playlists, media sources, and instances.
    func loadData() {
        loadChannels()
        loadPlaylists()
        loadSources()
    }

    /// Loads channel items from subscriptions.
    private func loadChannels() {
        guard let dataManager else { return }

        // Cache subscriptions for use in avatarURL(for:)
        cachedSubscriptions = dataManager.subscriptions()
        let limitEnabled = settingsManager?.sidebarChannelsLimitEnabled ?? true
        let maxChannels = settingsManager?.sidebarMaxChannels ?? SettingsManager.defaultSidebarMaxChannels
        let sortOrder = settingsManager?.sidebarChannelSort ?? .lastUploaded

        // Sort subscriptions
        let sortedSubscriptions: [Subscription]
        switch sortOrder {
        case .alphabetical:
            sortedSubscriptions = cachedSubscriptions.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .recentlySubscribed:
            sortedSubscriptions = cachedSubscriptions.sorted { $0.subscribedAt > $1.subscribedAt }
        case .lastUploaded:
            sortedSubscriptions = cachedSubscriptions.sorted { sub1, sub2 in
                let date1 = sub1.lastVideoPublishedAt ?? .distantPast
                let date2 = sub2.lastVideoPublishedAt ?? .distantPast
                return date1 > date2
            }
        case .custom:
            // For custom, we'd need additional ordering data - for now fallback to alphabetical
            sortedSubscriptions = cachedSubscriptions.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }

        // Apply limit (if enabled) and convert to sidebar items
        if limitEnabled {
            channelItems = sortedSubscriptions
                .prefix(maxChannels)
                .map { SidebarItem.from(subscription: $0) }
        } else {
            channelItems = sortedSubscriptions
                .map { SidebarItem.from(subscription: $0) }
        }
    }

    /// Loads playlist items from local playlists.
    private func loadPlaylists() {
        guard let dataManager else { return }

        // Cache playlists for use in videoCount(for:)
        cachedPlaylists = dataManager.playlists()
        let sortOrder = settingsManager?.sidebarPlaylistSort ?? .alphabetical
        let limitEnabled = settingsManager?.sidebarPlaylistsLimitEnabled ?? false
        let maxPlaylists = settingsManager?.sidebarMaxPlaylists ?? SettingsManager.defaultSidebarMaxPlaylists

        // Sort playlists
        let sortedPlaylists: [LocalPlaylist]
        switch sortOrder {
        case .alphabetical:
            sortedPlaylists = cachedPlaylists.sorted(by: { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending })
        case .lastUpdated:
            sortedPlaylists = cachedPlaylists.sorted(by: { $0.updatedAt > $1.updatedAt })
        }

        // Apply limit if enabled
        if limitEnabled {
            playlistItems = sortedPlaylists
                .prefix(maxPlaylists)
                .map { SidebarItem.from(playlist: $0) }
        } else {
            playlistItems = sortedPlaylists
                .map { SidebarItem.from(playlist: $0) }
        }
    }

    /// Loads instance and media source items with sorting and limiting.
    /// Builds a unified sortedSourceItems list for display.
    private func loadSources() {
        let sortOrder = settingsManager?.sidebarSourceSort ?? .name
        let limitEnabled = settingsManager?.sidebarSourcesLimitEnabled ?? false
        let maxSources = settingsManager?.sidebarMaxSources ?? SettingsManager.defaultSidebarMaxSources

        // Get raw data
        let instances = instancesManager?.enabledInstances ?? []
        let mediaSources = mediaSourcesManager?.enabledSources ?? []

        // Build combined list with sort keys
        struct SourceEntry {
            let item: SidebarItem
            let name: String
            let date: Date
            let typeOrder: Int  // For type sorting: instances (0-99), media sources (100-199)
        }

        var entries: [SourceEntry] = []

        // Add instances
        for instance in instances {
            let item = SidebarItem.from(instance: instance)
            // Type order: group by instance type (invidious=0, piped=1, peertube=2, yatteeServer=3)
            let typeOrder: Int
            switch instance.type {
            case .invidious: typeOrder = 0
            case .piped: typeOrder = 1
            case .peertube: typeOrder = 2
            case .yatteeServer: typeOrder = 3
            }
            entries.append(SourceEntry(item: item, name: instance.displayName, date: instance.dateAdded, typeOrder: typeOrder))
        }

        // Add media sources (type order 100 to come after instances when sorting by type)
        for source in mediaSources {
            let item = SidebarItem.from(mediaSource: source)
            // All media sources use same typeOrder (100) to sort alphabetically together
            entries.append(SourceEntry(item: item, name: source.name, date: source.dateAdded, typeOrder: 100))
        }

        // Sort combined list
        switch sortOrder {
        case .name:
            entries.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .type:
            // Sort by type order, then by name within each type
            entries.sort { a, b in
                if a.typeOrder != b.typeOrder {
                    return a.typeOrder < b.typeOrder
                }
                return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
            }
        case .lastAdded:
            entries.sort { $0.date > $1.date }
        }

        // Apply limit if enabled
        if limitEnabled {
            entries = Array(entries.prefix(maxSources))
        }

        // Update the unified sorted list
        sortedSourceItems = entries.map { $0.item }

        // Also update legacy separate lists for backwards compatibility
        instanceItems = sortedSourceItems.filter { $0.isInstance }
        mediaSourceItems = sortedSourceItems.filter { $0.isMediaSource }
    }

    // MARK: - Notification Observers

    private func setupNotificationObservers() {
        NotificationCenter.default.publisher(for: .subscriptionsDidChange)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.loadChannels()
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .playlistsDidChange)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.loadPlaylists()
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .mediaSourcesDidChange)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.loadSources()
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .instancesDidChange)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.loadSources()
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .sidebarSettingsDidChange)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.loadData()
            }
            .store(in: &cancellables)
    }

    // MARK: - Channel Data Access

    /// Yattee Server URL for avatar fallback
    private var yatteeServerURL: URL? {
        instancesManager?.enabledYatteeServerInstances.first?.url
    }

    /// Returns avatar URL for a channel sidebar item.
    /// Uses AvatarURLBuilder for Yattee Server fallback when direct URL is unavailable.
    /// Uses cached subscriptions to avoid repeated DB queries during layout.
    func avatarURL(for item: SidebarItem) -> URL? {
        guard case .channel(let channelID, _, _) = item else { return nil }

        let directURL = cachedSubscriptions.first { $0.channelID == channelID }?.avatarURL

        return AvatarURLBuilder.avatarURL(
            channelID: channelID,
            directURL: directURL,
            serverURL: yatteeServerURL,
            size: 22  // Matches SidebarChannelIcon size
        )
    }

    // MARK: - Playlist Data Access

    /// Returns video count for a playlist sidebar item.
    /// Uses cached playlists to avoid repeated DB queries during layout.
    func videoCount(for item: SidebarItem) -> Int {
        guard case .playlist(let id, _) = item else { return 0 }

        return cachedPlaylists.first { $0.id == id }?.videoCount ?? 0
    }

    /// Returns thumbnail URL for a playlist sidebar item.
    /// Uses cached playlists to avoid repeated DB queries during layout.
    func thumbnailURL(for item: SidebarItem) -> URL? {
        guard case .playlist(let id, _) = item else { return nil }
        return cachedPlaylists.first { $0.id == id }?.thumbnailURL
    }
}

// MARK: - Channel Sort Order

/// Defines how channels are sorted in the sidebar.
enum SidebarChannelSort: String, Codable, CaseIterable, Identifiable {
    case alphabetical
    case recentlySubscribed
    case lastUploaded
    case custom

    var id: String { rawValue }

    var localizedTitle: String {
        switch self {
        case .alphabetical:
            return String(localized: "sidebar.sort.alphabetical")
        case .recentlySubscribed:
            return String(localized: "sidebar.sort.recentlySubscribed")
        case .lastUploaded:
            return String(localized: "sidebar.sort.lastUploaded")
        case .custom:
            return String(localized: "sidebar.sort.custom")
        }
    }
}

// MARK: - Playlist Sort Order

/// Defines how playlists are sorted in the sidebar.
enum SidebarPlaylistSort: String, Codable, CaseIterable, Identifiable {
    case alphabetical
    case lastUpdated

    var id: String { rawValue }

    var localizedTitle: String {
        switch self {
        case .alphabetical:
            return String(localized: "sidebar.playlist.sort.alphabetical")
        case .lastUpdated:
            return String(localized: "sidebar.playlist.sort.lastUpdated")
        }
    }
}

// MARK: - Source Sort Order

/// Defines how sources (instances + media sources) are sorted in the sidebar.
enum SidebarSourceSort: String, Codable, CaseIterable, Identifiable {
    case name
    case type       // Remote server vs files server
    case lastAdded

    var id: String { rawValue }

    var localizedTitle: String {
        switch self {
        case .name:
            return String(localized: "sidebar.source.sort.name")
        case .type:
            return String(localized: "sidebar.source.sort.type")
        case .lastAdded:
            return String(localized: "sidebar.source.sort.lastAdded")
        }
    }
}
