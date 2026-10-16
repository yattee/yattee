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
    /// Several links opened at once, resolved into mixed results.
    case openedLinks([URL])
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
            TVDownloadsUnavailableView(title: String(localized: "home.downloads.title"))
            #else
            DownloadsView()
            #endif
        case .downloadsStorage:
            #if os(tvOS)
            TVDownloadsUnavailableView(title: String(localized: "settings.downloads.storage.title"))
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
        case .openedLinks(let urls):
            OpenedLinksView(urls: urls)
        }
    }
}

#if os(tvOS)
// MARK: - tvOS Downloads Placeholder

/// What a downloads destination shows on tvOS, which has no downloads.
///
/// Reachable on tvOS through `yattee://downloads`. Without a focusable element
/// the focus engine has nowhere to land and the remote is stuck, so it carries
/// a Done that pops it.
private struct TVDownloadsUnavailableView: View {
    let title: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: "arrow.down.circle")
        } description: {
            Text(String(localized: "home.downloads.notAvailable"))
        } actions: {
            Button(String(localized: "common.done")) {
                dismiss()
            }
        }
    }
}
#endif

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
            } actions: {
                #if os(tvOS)
                // Nothing else here is focusable, and as a sidebar source this
                // is a tab root that Menu cannot pop.
                Button(String(localized: "navigation.sourceNotFound.openSources")) {
                    appEnvironment?.navigationCoordinator.router.select(.sources)
                }
                #endif
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
            .opaqueWindowBackground()
            .miniPlayerBottomClearance()
            .navigationDestination(for: NavigationDestination.self) { destination in
                Group {
                    if let transitionID = destination.transitionID {
                        destination.view()
                            .zoomTransitionDestination(id: transitionID)
                    } else {
                        destination.view()
                    }
                }
                .opaqueWindowBackground()
                .miniPlayerBottomClearance()
            }
    }
}

extension EnvironmentValues {
    /// Height of the split view's floating mini player, which every page in
    /// the detail column reserves as bottom safe area. Zero elsewhere.
    @Entry var miniPlayerBottomClearance: CGFloat = 0
}

/// Reserves the floating mini player's height at the bottom of a page.
private struct MiniPlayerBottomClearanceModifier: ViewModifier {
    @Environment(\.miniPlayerBottomClearance) private var clearance

    func body(content: Content) -> some View {
        #if os(iOS)
        content
            .safeAreaInset(edge: .bottom, spacing: 0) {
                Color.clear.frame(height: clearance)
            }
        #else
        content
        #endif
    }
}

private extension View {
    func miniPlayerBottomClearance() -> some View {
        modifier(MiniPlayerBottomClearanceModifier())
    }
}

extension View {
    /// Adds navigation destination handlers for all app navigation destinations.
    /// Use this on views within a NavigationStack that contain NavigationLink(value:).
    func withNavigationDestinations() -> some View {
        modifier(NavigationDestinationHandlerModifier())
    }
}
