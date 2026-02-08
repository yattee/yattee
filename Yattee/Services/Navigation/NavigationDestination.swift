//
//  NavigationDestination.swift
//  Yattee
//
//  Navigation destinations for the app.
//

import Foundation
import SwiftUI

/// Source for video navigation - either a loaded video or just an ID to fetch.
enum VideoSource: Hashable, Sendable {
    case id(VideoID)
    case loaded(Video)
}

/// Navigation destinations for the app.
enum NavigationDestination: Hashable {
    /// Video info page - can be initialized with either a loaded video or just an ID.
    case video(VideoSource, queueContext: VideoQueueContext? = nil)
    case channel(String, ContentSource)
    case playlist(PlaylistSource)
    case continueWatching
    case downloads
    case downloadsStorage
    case subscriptionsFeed
    case settings
    case playlists
    case bookmarks
    case history
    case manageChannels
    case search(String)
    /// External video URL to be extracted via Yattee Server.
    case externalVideo(URL)
    /// External channel URL to be extracted via Yattee Server.
    case externalChannel(URL)
    /// Direct media URL (mp4, m3u8, etc.) to play without extraction.
    case directMedia(URL)
    /// Media sources list.
    case mediaSources
    /// Browse a specific media source by ID (for sidebar navigation).
    case mediaSource(UUID)
    /// Browse a specific media source at a path.
    case mediaBrowser(MediaSource, path: String, showOnlyPlayable: Bool = false)
    /// Browse a specific instance (Popular/Trending).
    case instanceBrowse(Instance, initialTab: InstanceBrowseView.BrowseTab? = nil)
    /// Import subscriptions from an instance.
    case importSubscriptions(instance: Instance)
    /// Import playlists from an instance.
    case importPlaylists(instance: Instance)
}

extension NavigationDestination {
    /// Returns the transition ID for zoom navigation animations, if applicable.
    ///
    /// Used to connect source views (NavigationLinks) with destination views
    /// for smooth zoom transitions. Returns nil for destinations that don't
    /// support zoom transitions.
    var transitionID: AnyHashable? {
        switch self {
        case .video(let source, _):
            switch source {
            case .id(let videoID): return videoID
            case .loaded(let video): return video.id
            }
        case .channel(let channelID, _):
            return channelID
        case .playlist(let source):
            return source.transitionID
        default:
            return nil
        }
    }

    @ViewBuilder
    func view() -> some View {
        switch self {
        case .video(let source, let queueContext):
            switch source {
            case .id(let videoID):
                VideoInfoView(videoID: videoID)
                    .videoQueueContext(queueContext)
            case .loaded(let video):
                VideoInfoView(video: video)
                    .videoQueueContext(queueContext)
            }
        case .channel(let channelID, let source):
            ChannelView(channelID: channelID, source: source)
        case .playlist(let source):
            UnifiedPlaylistDetailView(source: source)
        case .continueWatching:
            ContinueWatchingView()
        case .downloads:
            #if os(tvOS)
            ContentUnavailableView {
                Label(String(localized: "home.downloads.title"), systemImage: "arrow.down.circle")
            } description: {
                Text(String(localized: "home.downloads.notAvailable"))
            }
            #else
            DownloadsView()
            #endif
        case .downloadsStorage:
            #if os(tvOS)
            ContentUnavailableView {
                Label(String(localized: "settings.downloads.storage.title"), systemImage: "arrow.down.circle")
            } description: {
                Text(String(localized: "home.downloads.notAvailable"))
            }
            #else
            DownloadsStorageView()
            #endif
        case .subscriptionsFeed:
            SubscriptionsView()
        case .settings:
            SettingsView()
        case .playlists:
            PlaylistsListView()
        case .bookmarks:
            BookmarksListView()
        case .history:
            HistoryListView()
        case .manageChannels:
            ManageChannelsView()
        case .search(let query):
            SearchView(initialQuery: query)
        case .externalVideo(let url):
            ExternalVideoView(url: url)
        case .directMedia(let url):
            // Direct media URLs are typically handled inline by OpenLinkSheet,
            // but if navigated to directly, show video info with the created video
            VideoInfoView(video: DirectMediaHelper.createVideo(from: url))
        case .externalChannel(let url):
            // Use unified ChannelView with external channel URL
            ChannelView(
                channelID: url.absoluteString,
                source: .extracted(extractor: "external", originalURL: url),
                channelURL: url
            )
        case .mediaSources:
            MediaSourcesView()
        case .mediaSource(let id):
            MediaSourceByIDView(sourceID: id)
        case .mediaBrowser(let source, let path, let showOnlyPlayable):
            MediaBrowserView(source: source, path: path, showOnlyPlayable: showOnlyPlayable)
        case .instanceBrowse(let instance, let initialTab):
            InstanceBrowseView(instance: instance, initialTab: initialTab)
        case .importSubscriptions(let instance):
            ImportSubscriptionsView(instance: instance)
        case .importPlaylists(let instance):
            ImportPlaylistsView(instance: instance)
        }
    }
}

// MARK: - Media Source by ID View

/// Helper view that looks up a MediaSource by ID and shows MediaBrowserView.
private struct MediaSourceByIDView: View {
    let sourceID: UUID
    @Environment(\.appEnvironment) private var appEnvironment

    var body: some View {
        if let source = appEnvironment?.mediaSourcesManager.source(byID: sourceID) {
            MediaBrowserView(source: source, path: "/")
        } else {
            ContentUnavailableView {
                Label(String(localized: "navigation.sourceNotFound"), systemImage: "externaldrive.badge.exclamationmark")
            } description: {
                Text(String(localized: "navigation.sourceNotFound.description"))
            }
        }
    }
}

// MARK: - Navigation Destination Modifier

/// A view modifier that registers navigation destination handlers for all app destinations.
/// Apply this to views that contain NavigationLink(value: NavigationDestination) to ensure
/// the navigation stack can resolve all destination types.
///
/// Also applies zoom navigation transitions for supported destinations (video, channel, playlist)
/// when a zoom transition namespace is available in the environment.
struct NavigationDestinationHandlerModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .navigationDestination(for: NavigationDestination.self) { destination in
                if let transitionID = destination.transitionID {
                    destination.view()
                        .zoomTransitionDestination(id: transitionID)
                } else {
                    destination.view()
                }
            }
    }
}

extension View {
    /// Adds navigation destination handlers for all app navigation destinations.
    /// Use this on views within a NavigationStack that contain NavigationLink(value:).
    func withNavigationDestinations() -> some View {
        modifier(NavigationDestinationHandlerModifier())
    }
}
