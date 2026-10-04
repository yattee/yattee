//
//  NavigationTests.swift
//  YatteeTests
//
//  Tests for navigation components.
//

import Testing
import Foundation
import SwiftUI
@testable import Yattee

// MARK: - URLRouter Tests

@Suite("URLRouter Tests")
struct URLRouterTests {
    let router = URLRouter()

    // MARK: - YouTube URL Tests

    @Test("Parse standard YouTube watch URL")
    func standardWatchURL() {
        let url = URL(string: "https://www.youtube.com/watch?v=dQw4w9WgXcQ")!
        let destination = router.route(url)

        if case .video(let source, _) = destination, case .id(let videoID) = source {
            #expect(videoID.videoID == "dQw4w9WgXcQ")
            if case .global = videoID.source {
                // Expected
            } else {
                Issue.record("Expected global source")
            }
        } else {
            Issue.record("Expected video destination")
        }
    }

    @Test("Parse YouTube short URL")
    func shortURL() {
        let url = URL(string: "https://youtu.be/dQw4w9WgXcQ")!
        let destination = router.route(url)

        if case .video(let source, _) = destination, case .id(let videoID) = source {
            #expect(videoID.videoID == "dQw4w9WgXcQ")
        } else {
            Issue.record("Expected video destination")
        }
    }

    @Test("Parse YouTube embed URL")
    func embedURL() {
        let url = URL(string: "https://www.youtube.com/embed/dQw4w9WgXcQ")!
        let destination = router.route(url)

        if case .video(let source, _) = destination, case .id(let videoID) = source {
            #expect(videoID.videoID == "dQw4w9WgXcQ")
        } else {
            Issue.record("Expected video destination")
        }
    }

    @Test("Parse YouTube shorts URL")
    func shortsURL() {
        let url = URL(string: "https://www.youtube.com/shorts/abc123def")!
        let destination = router.route(url)

        if case .video(let source, _) = destination, case .id(let videoID) = source {
            #expect(videoID.videoID == "abc123def")
        } else {
            Issue.record("Expected video destination")
        }
    }

    @Test("Parse YouTube watch URL with timestamp")
    func watchURLWithTimestamp() {
        let url = URL(string: "https://www.youtube.com/watch?v=dQw4w9WgXcQ&t=120")!
        let destination = router.route(url)

        if case .video(let source, _) = destination, case .id(let videoID) = source {
            #expect(videoID.videoID == "dQw4w9WgXcQ")
        } else {
            Issue.record("Expected video destination")
        }
    }

    @Test("Parse YouTube live URL")
    func liveURL() {
        let url = URL(string: "https://www.youtube.com/live/abc123def")!
        let destination = router.route(url)

        if case .video(let source, _) = destination, case .id(let videoID) = source {
            #expect(videoID.videoID == "abc123def")
        } else {
            Issue.record("Expected video destination")
        }
    }

    @Test("Parse mobile YouTube URL")
    func mobileURL() {
        let url = URL(string: "https://m.youtube.com/watch?v=dQw4w9WgXcQ")!
        let destination = router.route(url)

        if case .video(let source, _) = destination, case .id(let videoID) = source {
            #expect(videoID.videoID == "dQw4w9WgXcQ")
        } else {
            Issue.record("Expected video destination")
        }
    }

    // MARK: - Timestamp Parsing Tests

    @Test("Parse timestamp from youtu.be short URL")
    func timestampFromShortURL() {
        let url = URL(string: "https://youtu.be/GBimVR2VBQU?t=17097")!
        #expect(router.parseTimestamp(url) == 17097)
    }

    @Test("Parse compound timestamp value")
    func compoundTimestampValue() {
        #expect(URLRouter.parseTimestampValue("1h2m3s") == 3723)
        #expect(URLRouter.parseTimestampValue("2m30s") == 150)
        #expect(URLRouter.parseTimestampValue("90s") == 90)
        #expect(URLRouter.parseTimestampValue("90.5") == 90.5)
    }

    @Test("Reject non-finite and negative plain timestamp values")
    func rejectInvalidPlainTimestampValues() {
        // Plain numeric values that are accepted by TimeInterval(_:) but are not
        // valid seek targets must return nil rather than poisoning the player.
        #expect(URLRouter.parseTimestampValue("inf") == nil)
        #expect(URLRouter.parseTimestampValue("infinity") == nil)
        #expect(URLRouter.parseTimestampValue("nan") == nil)
        #expect(URLRouter.parseTimestampValue("-5") == nil)
        // Valid plain seconds still parse.
        #expect(URLRouter.parseTimestampValue("0") == 0)
        #expect(URLRouter.parseTimestampValue("90") == 90)
        #expect(URLRouter.parseTimestampValue("90.5") == 90.5)
    }

    // MARK: - Share Extension Wrapper Tests

    @Test("Unwrap yattee://open wrapper to inner URL with timestamp")
    func unwrapOpenWrapper() {
        // Share extension percent-encoding leaves ?, /, : intact - this is the literal form delivered
        let wrapper = URL(string: "yattee://open?url=https://youtu.be/GBimVR2VBQU?t=17097")!
        let inner = router.unwrapped(wrapper)

        #expect(inner.absoluteString == "https://youtu.be/GBimVR2VBQU?t=17097")
        #expect(router.parseTimestamp(inner) == 17097)

        // Unwrapped URL still routes to the right video
        if case .video(let source, _) = router.route(inner), case .id(let videoID) = source {
            #expect(videoID.videoID == "GBimVR2VBQU")
        } else {
            Issue.record("Expected video destination")
        }
    }

    @Test("Unwrap wrapper with ampersand timestamp form")
    func unwrapOpenWrapperAmpersandForm() {
        let wrapper = URL(string: "yattee://open?url=https://www.youtube.com/watch?v=dQw4w9WgXcQ&t=120")!
        let inner = router.unwrapped(wrapper)

        #expect(router.parseTimestamp(inner) == 120)
        if case .video(let source, _) = router.route(inner), case .id(let videoID) = source {
            #expect(videoID.videoID == "dQw4w9WgXcQ")
        } else {
            Issue.record("Expected video destination")
        }
    }

    @Test("Unwrapped returns non-wrapper URLs unchanged")
    func unwrapPassthrough() {
        let plain = URL(string: "https://youtu.be/dQw4w9WgXcQ?t=42")!
        #expect(router.unwrapped(plain) == plain)

        let scheme = URL(string: "yattee://subscriptions")!
        #expect(router.unwrapped(scheme) == scheme)
    }

    // MARK: - PeerTube URL Tests

    @Test("Parse PeerTube /w/ video URL")
    func peertubeWURL() {
        let url = URL(string: "https://framatube.org/w/abc123-def456-ghi789")!
        let destination = router.route(url)

        if case .video(let source, _) = destination, case .id(let videoID) = source {
            #expect(videoID.videoID == "abc123-def456-ghi789")
            if case .federated(_, let instance) = videoID.source {
                #expect(instance.host == "framatube.org")
            } else {
                Issue.record("Expected federated source")
            }
        } else {
            Issue.record("Expected video destination")
        }
    }

    @Test("Parse PeerTube /videos/watch/ URL")
    func peertubeVideosWatchURL() {
        let url = URL(string: "https://peertube.social/videos/watch/abc123")!
        let destination = router.route(url)

        if case .video(let source, _) = destination, case .id(let videoID) = source {
            #expect(videoID.videoID == "abc123")
            if case .federated(_, let instance) = videoID.source {
                #expect(instance.host == "peertube.social")
            } else {
                Issue.record("Expected federated source")
            }
        } else {
            Issue.record("Expected video destination")
        }
    }

    // MARK: - Custom Scheme Tests

    @Test("Parse yattee:// video URL")
    func customSchemeVideoURL() {
        let url = URL(string: "yattee://video/dQw4w9WgXcQ")!
        let destination = router.route(url)

        if case .video(let source, _) = destination, case .id(let videoID) = source {
            #expect(videoID.videoID == "dQw4w9WgXcQ")
        } else {
            Issue.record("Expected video destination")
        }
    }

    @Test("Parse yattee:// channel URL")
    func customSchemeChannelURL() {
        let url = URL(string: "yattee://channel/UCtest123")!
        let destination = router.route(url)

        if case .channel(let channelID, _) = destination {
            #expect(channelID == "UCtest123")
        } else {
            Issue.record("Expected channel destination")
        }
    }

    // MARK: - Edge Cases

    @Test("Unknown URL routes to external video for yt-dlp extraction")
    func unknownURL() {
        let url = URL(string: "https://example.com/something")!
        let destination = router.route(url)
        // Unknown URLs are now routed to externalVideo for potential yt-dlp extraction
        if case .externalVideo(let extractedURL) = destination {
            #expect(extractedURL == url)
        } else {
            Issue.record("Expected externalVideo destination for unknown URLs")
        }
    }

    @Test("YouTube URL without video ID routes to external video")
    func urlWithoutVideoID() {
        let url = URL(string: "https://www.youtube.com/watch")!
        let destination = router.route(url)
        // YouTube URLs without video ID are now treated as potential external videos
        if case .externalVideo(let extractedURL) = destination {
            #expect(extractedURL == url)
        } else {
            Issue.record("Expected externalVideo destination")
        }
    }

    @Test("Known non-PeerTube hosts route to external video")
    func nonPeerTubeHosts() {
        // Vimeo should not be parsed as PeerTube but routed to external video
        let vimeoURL = URL(string: "https://vimeo.com/w/123456")!
        let vimeoDestination = router.route(vimeoURL)
        if case .externalVideo(let url) = vimeoDestination {
            #expect(url == vimeoURL)
        } else {
            Issue.record("Expected externalVideo destination for Vimeo")
        }

        // Dailymotion should not be parsed as PeerTube but routed to external video
        let dailymotionURL = URL(string: "https://dailymotion.com/w/123456")!
        let dailymotionDestination = router.route(dailymotionURL)
        if case .externalVideo(let url) = dailymotionDestination {
            #expect(url == dailymotionURL)
        } else {
            Issue.record("Expected externalVideo destination for Dailymotion")
        }
    }

    // MARK: - External Host Exclusion Tests

    @Test("www.duckduckgo.com is excluded from external video routing")
    func wwwDuckDuckGoExcluded() {
        let url = URL(string: "https://www.duckduckgo.com/?q=cat+videos")!
        let destination = router.route(url)
        if case .externalVideo = destination {
            Issue.record("www.duckduckgo.com must not route to externalVideo; yt-dlp extraction should not run for a search engine")
        }
    }

    @Test("duckduckgo.com bare host remains excluded from external video")
    func duckDuckGoBareExcluded() {
        let url = URL(string: "https://duckduckgo.com/?q=test")!
        let destination = router.route(url)
        if case .externalVideo = destination {
            Issue.record("duckduckgo.com must not route to externalVideo; yt-dlp extraction should not run for a search engine")
        }
    }

    // MARK: - YouTube Channel URL Tests

    @Test("Parse YouTube channel URL")
    func parseChannelURL() {
        let url = URL(string: "https://www.youtube.com/channel/UCxyz123")!
        let channelID = router.parseYouTubeChannelURL(url)
        #expect(channelID == "UCxyz123")
    }

    @Test("Parse YouTube handle URL")
    func parseHandleURL() {
        let url = URL(string: "https://www.youtube.com/@channelhandle")!
        let channelID = router.parseYouTubeChannelURL(url)
        #expect(channelID == "@channelhandle")
    }

    @Test("Parse YouTube /c/ custom URL")
    func parseCustomURL() {
        let url = URL(string: "https://www.youtube.com/c/CustomName")!
        let channelID = router.parseYouTubeChannelURL(url)
        #expect(channelID == "CustomName")
    }

    @Test("Parse YouTube /user/ URL")
    func parseUserURL() {
        let url = URL(string: "https://www.youtube.com/user/Username")!
        let channelID = router.parseYouTubeChannelURL(url)
        #expect(channelID == "Username")
    }

    @Test("Non-YouTube channel URL returns nil")
    func nonYouTubeChannelURL() {
        let url = URL(string: "https://example.com/channel/test")!
        let channelID = router.parseYouTubeChannelURL(url)
        #expect(channelID == nil)
    }

    // MARK: - YouTube Playlist URL Tests

    @Test("Parse YouTube playlist URL")
    func parsePlaylistURL() {
        let url = URL(string: "https://www.youtube.com/playlist?list=PLtest123")!
        let destination = router.route(url)

        if case .playlist(.remote(let playlistID, _, _, _)) = destination {
            #expect(playlistID.playlistID == "PLtest123")
            if case .global = playlistID.source {
                // Expected
            } else {
                Issue.record("Expected global source")
            }
        } else {
            Issue.record("Expected playlist destination")
        }
    }

    @Test("YouTube watch URL with list parameter routes to video not playlist")
    func watchURLWithListParameter() {
        // When a URL has both v= and list=, it's a video playing within a playlist
        // We should route to the video, not the playlist
        let url = URL(string: "https://www.youtube.com/watch?v=dQw4w9WgXcQ&list=PLtest123")!
        let destination = router.route(url)

        if case .video(let source, _) = destination, case .id(let videoID) = source {
            #expect(videoID.videoID == "dQw4w9WgXcQ")
        } else {
            Issue.record("Expected video destination for watch URL with list parameter")
        }
    }

    // MARK: - YouTube Channel URL Routing Tests

    @Test("Parse and route YouTube channel URL")
    func routeChannelURL() {
        let url = URL(string: "https://www.youtube.com/channel/UCxyz123")!
        let destination = router.route(url)

        if case .channel(let channelID, let source) = destination {
            #expect(channelID == "UCxyz123")
            if case .global = source {
                // Expected
            } else {
                Issue.record("Expected global source")
            }
        } else {
            Issue.record("Expected channel destination")
        }
    }

    @Test("Parse and route YouTube handle URL")
    func routeHandleURL() {
        let url = URL(string: "https://www.youtube.com/@channelhandle")!
        let destination = router.route(url)

        if case .channel(let channelID, _) = destination {
            #expect(channelID == "@channelhandle")
        } else {
            Issue.record("Expected channel destination for handle URL")
        }
    }

    // MARK: - Custom Scheme Deep Link Tests

    @Test("Parse yattee:// search URL")
    func customSchemeSearchURL() {
        let url = URL(string: "yattee://search?q=hello%20world")!
        let destination = router.route(url)

        if case .search(let query) = destination {
            #expect(query == "hello world")
        } else {
            Issue.record("Expected search destination")
        }
    }

    @Test("Parse yattee:// search URL without query returns nil")
    func customSchemeSearchURLNoQuery() {
        let url = URL(string: "yattee://search")!
        let destination = router.route(url)
        #expect(destination == nil)
    }

    @Test("Parse yattee:// playlist URL")
    func customSchemePlaylistURL() {
        let url = URL(string: "yattee://playlist/PLtest123")!
        let destination = router.route(url)

        if case .playlist(.remote(let playlistID, _, _, _)) = destination {
            #expect(playlistID.playlistID == "PLtest123")
        } else {
            Issue.record("Expected playlist destination")
        }
    }

    @Test("Parse yattee:// playlists URL")
    func customSchemePlaylistsURL() {
        let url = URL(string: "yattee://playlists")!
        let destination = router.route(url)
        #expect(destination == .playlists)
    }

    @Test("Parse yattee:// bookmarks URL")
    func customSchemeBookmarksURL() {
        let url = URL(string: "yattee://bookmarks")!
        let destination = router.route(url)
        #expect(destination == .bookmarks)
    }

    @Test("Parse yattee:// history URL")
    func customSchemeHistoryURL() {
        let url = URL(string: "yattee://history")!
        let destination = router.route(url)
        #expect(destination == .history)
    }

    @Test("Parse yattee:// downloads URL")
    func customSchemeDownloadsURL() {
        let url = URL(string: "yattee://downloads")!
        let destination = router.route(url)
        #expect(destination == .downloads)
    }

    @Test("Parse yattee:// channels URL")
    func customSchemeChannelsURL() {
        let url = URL(string: "yattee://channels")!
        let destination = router.route(url)
        #expect(destination == .manageChannels)
    }

    @Test("Parse yattee:// subscriptions URL")
    func customSchemeSubscriptionsURL() {
        let url = URL(string: "yattee://subscriptions")!
        let destination = router.route(url)
        #expect(destination == .subscriptionsFeed)
    }

    @Test("Parse yattee:// continue-watching URL")
    func customSchemeContinueWatchingURL() {
        let url = URL(string: "yattee://continue-watching")!
        let destination = router.route(url)
        #expect(destination == .continueWatching)
    }

    @Test("Parse yattee:// settings URL")
    func customSchemeSettingsURL() {
        let url = URL(string: "yattee://settings")!
        let destination = router.route(url)
        #expect(destination == .settings)
    }

    @Test("Parse yattee:// channel URL with PeerTube source")
    func customSchemeChannelURLWithPeerTubeSource() {
        let url = URL(string: "yattee://channel/channelid123?source=peertube&instance=https://peertube.social")!
        let destination = router.route(url)

        if case .channel(let channelID, let source) = destination {
            #expect(channelID == "channelid123")
            if case .federated(_, let instance) = source {
                #expect(instance.host == "peertube.social")
            } else {
                Issue.record("Expected federated source")
            }
        } else {
            Issue.record("Expected channel destination with federated source")
        }
    }

    @Test("Parse yattee:// channel URL with PeerTube source but no instance falls back to Global")
    func customSchemeChannelURLPeerTubeNoInstance() {
        // If source=peertube but no instance is provided, should fall back to Global
        let url = URL(string: "yattee://channel/channelid123?source=peertube")!
        let destination = router.route(url)

        if case .channel(let channelID, let source) = destination {
            #expect(channelID == "channelid123")
            if case .global = source {
                // Expected - falls back to global when instance missing
            } else {
                Issue.record("Expected global source fallback")
            }
        } else {
            Issue.record("Expected channel destination")
        }
    }
}

// MARK: - NavigationDestination Tests

@Suite("NavigationDestination Tests")
struct NavigationDestinationTests {

    @Test("Video destinations are hashable")
    func videoHashable() {
        let video1 = NavigationDestination.video(.id(.global("abc")))
        let video2 = NavigationDestination.video(.id(.global("abc")))
        let video3 = NavigationDestination.video(.id(.global("def")))

        #expect(video1 == video2)
        #expect(video1 != video3)
    }

    @Test("Different destination types are not equal")
    func differentTypes() {
        let video = NavigationDestination.video(.id(.global("abc")))
        let channel = NavigationDestination.channel("abc", .global(provider: ContentSource.youtubeProvider))

        #expect(video != channel)
    }

    @Test("Settings destination")
    func settingsDestination() {
        let settings1 = NavigationDestination.settings
        let settings2 = NavigationDestination.settings

        #expect(settings1 == settings2)
    }

    @Test("Downloads destination")
    func downloadsDestination() {
        let downloads1 = NavigationDestination.downloads
        let downloads2 = NavigationDestination.downloads

        #expect(downloads1 == downloads2)
    }

    @Test("Search destination with query")
    func searchDestination() {
        let search1 = NavigationDestination.search("hello world")
        let search2 = NavigationDestination.search("hello world")
        let search3 = NavigationDestination.search("different query")

        #expect(search1 == search2)
        #expect(search1 != search3)
    }

    @Test("Playlist destination")
    func playlistDestination() {
        let playlist1 = NavigationDestination.playlist(.remote(PlaylistID(source: .global(provider: ContentSource.youtubeProvider), playlistID: "PLtest"), instance: nil))
        let playlist2 = NavigationDestination.playlist(.remote(PlaylistID(source: .global(provider: ContentSource.youtubeProvider), playlistID: "PLtest"), instance: nil))
        let playlist3 = NavigationDestination.playlist(.remote(PlaylistID(source: .global(provider: ContentSource.youtubeProvider), playlistID: "PLother"), instance: nil))

        #expect(playlist1 == playlist2)
        #expect(playlist1 != playlist3)
    }
}

// MARK: - NavigationCoordinator Tests

@Suite("NavigationCoordinator Tests")
@MainActor
struct NavigationCoordinatorTests {

    @Test("Initial state")
    func initialState() {
        let coordinator = NavigationCoordinator()

        #expect(coordinator.router.selection == .home)
        #expect(coordinator.router.stack(for: .home).isEmpty)
    }

    @Test("Navigate pushes onto the selected section's stack")
    func navigateToDestination() {
        let coordinator = NavigationCoordinator()
        let destination = NavigationDestination.video(.id(.global("test123")))

        coordinator.navigate(to: destination)

        #expect(coordinator.router.stack(for: .home) == [destination])
    }

    @Test("Multiple navigations stack in order")
    func multipleNavigations() {
        let coordinator = NavigationCoordinator()

        coordinator.navigate(to: .video(.id(.global("1"))))
        coordinator.navigate(to: .video(.id(.global("2"))))
        coordinator.navigate(to: .video(.id(.global("3"))))

        #expect(coordinator.router.stack(for: .home) == [
            .video(.id(.global("1"))),
            .video(.id(.global("2"))),
            .video(.id(.global("3"))),
        ])
    }

    @Test("Each section keeps its own stack")
    func perSectionStacks() {
        let coordinator = NavigationCoordinator()

        coordinator.navigate(to: .video(.id(.global("1"))))
        coordinator.router.select(.search)
        coordinator.navigate(to: .video(.id(.global("2"))))

        #expect(coordinator.router.stack(for: .home) == [.video(.id(.global("1")))])
        #expect(coordinator.router.stack(for: .search) == [.video(.id(.global("2")))])
    }

    @Test("Pop to root clears the selected stack only")
    func popToRoot() {
        let coordinator = NavigationCoordinator()
        coordinator.navigate(to: .video(.id(.global("1"))))
        coordinator.router.select(.search)
        coordinator.navigate(to: .video(.id(.global("2"))))

        coordinator.router.popToRoot()

        #expect(coordinator.router.stack(for: .search).isEmpty)
        #expect(coordinator.router.stack(for: .home).count == 1)
    }

    @Test("Navigate to subscriptions selects the feed")
    func navigateToSubscriptions() {
        let coordinator = NavigationCoordinator()

        coordinator.navigateToSubscriptions()

        #expect(coordinator.router.selection == .subscriptionsFeed)
    }

    @Test("Startup tab applies only once")
    func startupTabOnce() {
        let router = NavigationRouter()

        router.applyStartupTabIfNeeded(.search)
        router.select(.bookmarks)
        router.applyStartupTabIfNeeded(.search)

        #expect(router.selection == .bookmarks)
    }

    @Test("A stack that is no longer selected can't clear itself")
    func offscreenStackWriteIgnored() {
        let router = NavigationRouter()
        router.push(.history)
        let homePath = router.path(for: .home)

        router.select(.bookmarks)
        homePath.wrappedValue = []

        #expect(router.stack(for: .home) == [.history])
    }

    @Test("The selected stack still pops")
    func selectedStackPops() {
        let router = NavigationRouter()
        router.push(.history)

        router.path(for: .home).wrappedValue = []

        #expect(router.stack(for: .home).isEmpty)
    }

    @Test("A destination pushed before startup keeps its section")
    func deepLinkBeforeStartup() {
        let coordinator = NavigationCoordinator()

        coordinator.navigate(to: .video(.id(.global("deep"))))
        coordinator.router.applyStartupTabIfNeeded(.search)

        #expect(coordinator.router.selection == .home)
        #expect(coordinator.router.stack(for: .home) == [.video(.id(.global("deep")))])
    }
}

// MARK: - NavigationRouter Layout Mapping Tests

@Suite("NavigationRouter Layout Mapping Tests")
@MainActor
struct NavigationRouterLayoutMappingTests {

    @Test("Available selection is left alone")
    func availableSelectionUnchanged() {
        let router = NavigationRouter()
        router.select(.bookmarks)
        router.push(.video(.id(.global("1"))))

        router.ensureSelectionIsAvailable(isAvailable: { _ in true })

        #expect(router.selection == .bookmarks)
        #expect(router.stack(for: .bookmarks).count == 1)
    }

    @Test("Sidebar channel maps to the subscriptions tab with the channel pushed first")
    func channelToSubscriptions() {
        let router = NavigationRouter()
        let source = ContentSource.global(provider: ContentSource.youtubeProvider)
        let channel = SidebarItem.channel(channelID: "UC1", name: "Channel", source: source)
        router.select(channel)
        router.push(.video(.id(.global("v1"))))

        router.ensureSelectionIsAvailable(isAvailable: { [.home, .search, .subscriptionsFeed].contains($0) })

        #expect(router.selection == .subscriptionsFeed)
        #expect(router.stack(for: .subscriptionsFeed) == [.channel("UC1", source), .video(.id(.global("v1")))])
        #expect(router.stack(for: channel).isEmpty)
    }

    @Test("Hidden tab falls back to home with its screen pushed")
    func hiddenTabToHome() {
        let router = NavigationRouter()
        router.select(.bookmarks)
        router.push(.video(.id(.global("v1"))))

        router.ensureSelectionIsAvailable(isAvailable: { [.home, .search].contains($0) })

        #expect(router.selection == .home)
        #expect(router.stack(for: .home) == [.bookmarks, .video(.id(.global("v1")))])
    }

    @Test("Sidebar playlist maps to the playlists tab")
    func playlistToPlaylists() {
        let router = NavigationRouter()
        let id = UUID()
        router.select(.playlist(id: id, title: "Mix"))

        router.ensureSelectionIsAvailable(isAvailable: { [.home, .search, .playlistsList].contains($0) })

        #expect(router.selection == .playlistsList)
        #expect(router.stack(for: .playlistsList) == [.playlist(.local(id, title: "Mix"))])
    }
}

// MARK: - ConnectivityMonitor Tests

@Suite("ConnectivityMonitor Tests")
@MainActor
struct ConnectivityMonitorTests {

    @Test("Initial state assumes online")
    func initialState() {
        let monitor = ConnectivityMonitor()

        // By default, assume online until NWPathMonitor reports otherwise
        #expect(monitor.isOnline == true)
    }
}
