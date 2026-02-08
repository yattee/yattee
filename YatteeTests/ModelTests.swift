//
//  ModelTests.swift
//  YatteeTests
//
//  Tests for core model types.
//

import Testing
import Foundation
@testable import Yattee

// MARK: - ContentSource Tests

@Suite("ContentSource Tests")
@MainActor
struct ContentSourceTests {

    @Test("Global source equality")
    func globalEquality() {
        let source1 = ContentSource.global(provider: ContentSource.youtubeProvider)
        let source2 = ContentSource.global(provider: ContentSource.youtubeProvider)
        #expect(source1 == source2)
    }

    @Test("Federated source with same instance are equal")
    func federatedEqualitySameInstance() {
        let url = URL(string: "https://peertube.example.com")!
        let source1 = ContentSource.federated(provider: ContentSource.peertubeProvider, instance: url)
        let source2 = ContentSource.federated(provider: ContentSource.peertubeProvider, instance: url)
        #expect(source1 == source2)
    }

    @Test("Federated sources with different instances are not equal")
    func federatedEqualityDifferentInstances() {
        let url1 = URL(string: "https://peertube1.example.com")!
        let url2 = URL(string: "https://peertube2.example.com")!
        let source1 = ContentSource.federated(provider: ContentSource.peertubeProvider, instance: url1)
        let source2 = ContentSource.federated(provider: ContentSource.peertubeProvider, instance: url2)
        #expect(source1 != source2)
    }

    @Test("Global and Federated are not equal")
    func globalNotEqualToFederated() {
        let global = ContentSource.global(provider: ContentSource.youtubeProvider)
        let federated = ContentSource.federated(provider: ContentSource.peertubeProvider, instance: URL(string: "https://example.com")!)
        #expect(global != federated)
    }

    @Test("ContentSource display names")
    func displayNames() {
        #expect(ContentSource.global(provider: ContentSource.youtubeProvider).displayName == "YouTube")

        let peertubeURL = URL(string: "https://framatube.org")!
        #expect(ContentSource.federated(provider: ContentSource.peertubeProvider, instance: peertubeURL).displayName == "framatube.org")
    }

    @Test("ContentSource short names")
    func shortNames() {
        #expect(ContentSource.global(provider: ContentSource.youtubeProvider).shortName == "YT")

        let peertubeURL = URL(string: "https://framatube.org")!
        #expect(ContentSource.federated(provider: ContentSource.peertubeProvider, instance: peertubeURL).shortName == "framatub")
    }

    @Test("ContentSource is Codable")
    func codable() throws {
        let sources: [ContentSource] = [
            .global(provider: ContentSource.youtubeProvider),
            .federated(provider: ContentSource.peertubeProvider, instance: URL(string: "https://example.com")!)
        ]

        for source in sources {
            let encoded = try JSONEncoder().encode(source)
            let decoded = try JSONDecoder().decode(ContentSource.self, from: encoded)
            #expect(source == decoded)
        }
    }

    @Test("ContentSource sorting - Global comes before Federated")
    func sorting() {
        let global = ContentSource.global(provider: ContentSource.youtubeProvider)
        let federated = ContentSource.federated(provider: ContentSource.peertubeProvider, instance: URL(string: "https://example.com")!)

        #expect(global < federated)
        #expect(!(federated < global))
    }
}

// MARK: - VideoID Tests

@Suite("VideoID Tests")
@MainActor
struct VideoIDTests {

    @Test("Global VideoID creation")
    func globalCreation() {
        let videoID = VideoID.global("dQw4w9WgXcQ")
        #expect(videoID.videoID == "dQw4w9WgXcQ")
        if case .global(let provider) = videoID.source {
            #expect(provider == ContentSource.youtubeProvider)
        } else {
            Issue.record("Expected global source")
        }
        #expect(videoID.uuid == nil)
    }

    @Test("Federated VideoID creation")
    func federatedCreation() {
        let instance = URL(string: "https://framatube.org")!
        let videoID = VideoID.federated("123", instance: instance, uuid: "abc-def")
        #expect(videoID.videoID == "123")
        if case .federated(let provider, let url) = videoID.source {
            #expect(provider == ContentSource.peertubeProvider)
            #expect(url == instance)
        } else {
            Issue.record("Expected federated source")
        }
        #expect(videoID.uuid == "abc-def")
    }

    @Test("VideoID identifiable ID format")
    func identifiableID() {
        let ytID = VideoID.global("abc123")
        #expect(ytID.id == "global:youtube:abc123")

        let ptID = VideoID.federated("456", instance: URL(string: "https://example.com")!)
        #expect(ptID.id == "federated:peertube:example.com:456")
    }
}

// MARK: - Video Tests

@Suite("Video Tests")
@MainActor
struct VideoTests {

    @Test("Video formatted duration - minutes and seconds")
    func formattedDurationMinutesSeconds() {
        let video = makeVideo(duration: 185) // 3:05
        #expect(video.formattedDuration == "3:05")
    }

    @Test("Video formatted duration - hours")
    func formattedDurationHours() {
        let video = makeVideo(duration: 3725) // 1:02:05
        #expect(video.formattedDuration == "1:02:05")
    }

    @Test("Video formatted duration - live shows LIVE")
    func formattedDurationLive() {
        let video = makeVideo(duration: 0, isLive: true)
        #expect(video.formattedDuration == "LIVE")
    }

    @Test("Video formatted view count - thousands")
    func formattedViewCountThousands() {
        let video = makeVideo(viewCount: 1500)
        #expect(video.formattedViewCount == "1.5K")
    }

    @Test("Video formatted view count - millions")
    func formattedViewCountMillions() {
        let video = makeVideo(viewCount: 2_500_000)
        #expect(video.formattedViewCount == "2.5M")
    }

    @Test("Video formatted view count - exact thousands")
    func formattedViewCountExactThousands() {
        let video = makeVideo(viewCount: 1000)
        #expect(video.formattedViewCount == "1K")
    }

    @Test("Video best thumbnail returns highest quality")
    func bestThumbnail() {
        let thumbnails = [
            Thumbnail(url: URL(string: "https://example.com/default.jpg")!, quality: .default),
            Thumbnail(url: URL(string: "https://example.com/maxres.jpg")!, quality: .maxres),
            Thumbnail(url: URL(string: "https://example.com/high.jpg")!, quality: .high),
        ]
        let video = makeVideo(thumbnails: thumbnails)
        #expect(video.bestThumbnail?.quality == .maxres)
    }

    private func makeVideo(
        duration: TimeInterval = 100,
        isLive: Bool = false,
        viewCount: Int? = nil,
        thumbnails: [Thumbnail] = []
    ) -> Video {
        Video(
            id: .global("test"),
            title: "Test Video",
            description: nil,
            author: Author(id: "channel", name: "Test Channel"),
            duration: duration,
            publishedAt: nil,
            publishedText: nil,
            viewCount: viewCount,
            likeCount: nil,
            thumbnails: thumbnails,
            isLive: isLive,
            isUpcoming: false,
            scheduledStartTime: nil
        )
    }
}

// MARK: - Instance Tests

@Suite("Instance Tests")
@MainActor
struct InstanceTests {

    @Test("Instance URL validation - valid HTTPS")
    func validateURLValidHTTPS() {
        let url = Instance.validateURL("https://invidious.io")
        #expect(url != nil)
        #expect(url?.scheme == "https")
    }

    @Test("Instance URL validation - preserves explicit HTTP for local servers")
    func validateURLPreservesHTTP() {
        // HTTP is preserved for local/private network servers (e.g., yt-dlp server)
        let url = Instance.validateURL("http://invidious.io")
        #expect(url?.scheme == "http")
    }

    @Test("Instance URL validation - adds HTTPS if missing")
    func validateURLAddsScheme() {
        let url = Instance.validateURL("invidious.io")
        #expect(url?.scheme == "https")
    }

    @Test("Instance URL validation - removes trailing slash")
    func validateURLRemovesTrailingSlash() {
        let url = Instance.validateURL("https://invidious.io/")
        #expect(url?.path == "" || !url!.absoluteString.hasSuffix("/"))
    }

    @Test("Instance URL validation - handles edge cases")
    func validateURLEdgeCases() {
        // URLComponents is lenient and encodes spaces
        let urlWithSpaces = Instance.validateURL("example with spaces")
        #expect(urlWithSpaces != nil) // Gets URL-encoded

        // Verifies scheme is added
        let simpleHost = Instance.validateURL("invidious.io")
        #expect(simpleHost?.scheme == "https")
    }

    @Test("Instance display name uses custom name if set")
    func displayNameCustom() {
        let instance = Instance(
            type: .invidious,
            url: URL(string: "https://invidious.io")!,
            name: "My Instance"
        )
        #expect(instance.displayName == "My Instance")
    }

    @Test("Instance display name falls back to host")
    func displayNameFallback() {
        let instance = Instance(
            type: .invidious,
            url: URL(string: "https://invidious.io")!
        )
        #expect(instance.displayName == "invidious.io")
    }

    @Test("Instance isYouTubeInstance for Invidious")
    func isYouTubeInstanceInvidious() {
        let instance = Instance(type: .invidious, url: URL(string: "https://example.com")!)
        #expect(instance.isYouTubeInstance == true)
        #expect(instance.isPeerTubeInstance == false)
    }

    @Test("Instance isYouTubeInstance for Piped")
    func isYouTubeInstancePiped() {
        let instance = Instance(type: .piped, url: URL(string: "https://example.com")!)
        #expect(instance.isYouTubeInstance == true)
        #expect(instance.isPeerTubeInstance == false)
    }

    @Test("Instance isPeerTubeInstance")
    func isPeerTubeInstance() {
        let instance = Instance(type: .peertube, url: URL(string: "https://example.com")!)
        #expect(instance.isYouTubeInstance == false)
        #expect(instance.isPeerTubeInstance == true)
    }
}

// MARK: - Channel Tests

@Suite("Channel Tests")
@MainActor
struct ChannelTests {

    @Test("Channel formatted subscriber count")
    func formattedSubscriberCount() {
        let channel = Channel(
            id: .global("test"),
            name: "Test Channel",
            subscriberCount: 1_500_000
        )
        #expect(channel.formattedSubscriberCount == "1.5M")
    }

    @Test("ChannelID identifiable ID format")
    func channelIDFormat() {
        let ytID = ChannelID.global("UC123")
        #expect(ytID.id == "global:youtube:UC123")

        let ptID = ChannelID.federated("channel", instance: URL(string: "https://example.com")!)
        #expect(ptID.id == "federated:peertube:example.com:channel")
    }
}

// MARK: - Stream Tests

@Suite("Stream Tests")
@MainActor
struct StreamTests {

    @Test("StreamResolution comparison")
    func resolutionComparison() {
        #expect(StreamResolution.p720 < StreamResolution.p1080)
        #expect(StreamResolution.p1080 < StreamResolution.p2160)
        #expect(!(StreamResolution.p1080 < StreamResolution.p720))
    }

    @Test("StreamResolution from height label")
    func resolutionFromLabel() {
        let res720 = StreamResolution(heightLabel: "720p")
        #expect(res720?.height == 720)

        let res1080 = StreamResolution(heightLabel: "1080")
        #expect(res1080?.height == 1080)
    }

    @Test("Stream quality label for video")
    func qualityLabelVideo() {
        let stream = Stream(
            url: URL(string: "https://example.com/video.mp4")!,
            resolution: .p1080,
            format: "mp4"
        )
        #expect(stream.qualityLabel == "1080p")
    }

    @Test("Stream quality label for audio")
    func qualityLabelAudio() {
        let stream = Stream(
            url: URL(string: "https://example.com/audio.m4a")!,
            resolution: nil,
            format: "m4a",
            isAudioOnly: true
        )
        #expect(stream.qualityLabel == "Audio")
    }

    @Test("Stream isNativelyPlayable for MP4 H264")
    func nativelyPlayableMp4() {
        let stream = Stream(
            url: URL(string: "https://example.com/video.mp4")!,
            resolution: .p1080,
            format: "mp4",
            videoCodec: "avc1.4d401f"
        )
        #expect(stream.isNativelyPlayable == true)
    }

    @Test("Stream isNativelyPlayable for WebM VP9")
    func nativelyPlayableWebm() {
        let stream = Stream(
            url: URL(string: "https://example.com/video.webm")!,
            resolution: .p1080,
            format: "webm",
            videoCodec: "vp9"
        )
        #expect(stream.isNativelyPlayable == false)
    }
}

// MARK: - Playlist Tests

@Suite("Playlist Tests")
@MainActor
struct PlaylistTests {

    @Test("PlaylistID local vs remote")
    func playlistIDLocalVsRemote() {
        let localID = PlaylistID.local("my-playlist")
        #expect(localID.isLocal == true)
        #expect(localID.id == "local:my-playlist")

        let remoteID = PlaylistID.global("PLtest123")
        #expect(remoteID.isLocal == false)
        #expect(remoteID.id == "global:youtube:PLtest123")
    }
}

// MARK: - Caption Tests

@Suite("Caption Tests")
struct CaptionTests {

    @Test("Caption isAutoGenerated detection")
    func isAutoGenerated() {
        let autoCaption = Caption(
            label: "English (auto-generated)",
            languageCode: "en",
            url: URL(string: "https://example.com/caption.vtt")!
        )
        #expect(autoCaption.isAutoGenerated == true)

        let manualCaption = Caption(
            label: "English",
            languageCode: "en",
            url: URL(string: "https://example.com/caption.vtt")!
        )
        #expect(manualCaption.isAutoGenerated == false)
    }

    @Test("Caption baseLanguageCode extracts base code")
    func baseLanguageCode() {
        let enUS = Caption(
            label: "English (US)",
            languageCode: "en-US",
            url: URL(string: "https://example.com/caption.vtt")!
        )
        #expect(enUS.baseLanguageCode == "en")

        let deDE = Caption(
            label: "German",
            languageCode: "de-DE",
            url: URL(string: "https://example.com/caption.vtt")!
        )
        #expect(deDE.baseLanguageCode == "de")

        let simple = Caption(
            label: "French",
            languageCode: "fr",
            url: URL(string: "https://example.com/caption.vtt")!
        )
        #expect(simple.baseLanguageCode == "fr")
    }

    @Test("Caption id is unique")
    func captionID() {
        let caption = Caption(
            label: "English",
            languageCode: "en",
            url: URL(string: "https://example.com/caption.vtt")!
        )
        #expect(caption.id == "en:English")
    }

    @Test("Caption displayName strips auto-generated suffix")
    func displayName() {
        let autoCaption = Caption(
            label: "English (auto-generated)",
            languageCode: "en",
            url: URL(string: "https://example.com/caption.vtt")!
        )
        // Should return localized name or stripped label
        #expect(!autoCaption.displayName.contains("auto-generated"))
    }

    @Test("Caption is Codable")
    func codable() throws {
        let caption = Caption(
            label: "Spanish",
            languageCode: "es",
            url: URL(string: "https://example.com/caption.vtt")!
        )
        let encoded = try JSONEncoder().encode(caption)
        let decoded = try JSONDecoder().decode(Caption.self, from: encoded)
        #expect(caption == decoded)
    }

    @Test("Caption is Hashable")
    func hashable() {
        let caption1 = Caption(
            label: "English",
            languageCode: "en",
            url: URL(string: "https://example.com/caption1.vtt")!
        )
        let caption2 = Caption(
            label: "English",
            languageCode: "en",
            url: URL(string: "https://example.com/caption1.vtt")!
        )
        let caption3 = Caption(
            label: "French",
            languageCode: "fr",
            url: URL(string: "https://example.com/caption2.vtt")!
        )

        var set = Set<Caption>()
        set.insert(caption1)
        set.insert(caption2)
        set.insert(caption3)

        #expect(set.count == 2)
    }
}

// MARK: - VideoRowStyle Tests

@Suite("VideoRowStyle Tests")
struct VideoRowStyleTests {

    @Test("Large style dimensions")
    func largeDimensions() {
        let style = VideoRowStyle.large
        #expect(style.thumbnailWidth == 160)
        #expect(style.thumbnailHeight == 90)
    }

    @Test("Regular style dimensions")
    func regularDimensions() {
        let style = VideoRowStyle.regular
        #expect(style.thumbnailWidth == 120)
        #expect(style.thumbnailHeight == 68)
    }

    @Test("Compact style dimensions")
    func compactDimensions() {
        let style = VideoRowStyle.compact
        #expect(style.thumbnailWidth == 70)
        #expect(style.thumbnailHeight == 39)
    }

    @Test("Aspect ratios are 16:9")
    func aspectRatios() {
        for style in [VideoRowStyle.large, .regular, .compact] {
            let ratio = style.thumbnailWidth / style.thumbnailHeight
            // 16:9 ≈ 1.77, allow small tolerance
            #expect(abs(ratio - 16.0/9.0) < 0.1)
        }
    }
}

// MARK: - HomeTab Tests

@Suite("HomeTab Tests")
struct HomeTabTests {

    @Test("All cases exist")
    func allCases() {
        let cases = HomeTab.allCases
        #expect(cases.contains(.playlists))
        #expect(cases.contains(.history))
        #expect(cases.contains(.downloads))
        #expect(cases.count == 3)
    }

    @Test("Titles are not empty")
    func titles() {
        for tab in HomeTab.allCases {
            #expect(!tab.title.isEmpty)
        }
    }

    @Test("Icons are valid SF Symbol names")
    func icons() {
        #expect(HomeTab.playlists.icon == "list.bullet.rectangle")
        #expect(HomeTab.history.icon == "clock")
        #expect(HomeTab.downloads.icon == "arrow.down.circle")
    }

    @Test("Identifiable id uses rawValue")
    func identifiableID() {
        for tab in HomeTab.allCases {
            #expect(tab.id == tab.rawValue)
        }
    }
}

// MARK: - PlayerInfoTab Tests

@Suite("PlayerInfoTab Tests")
struct PlayerInfoTabTests {

    @Test("All cases exist")
    func allCases() {
        let cases = PlayerInfoTab.allCases
        #expect(cases.contains(.description))
        #expect(cases.contains(.comments))
        #expect(cases.count == 2)
    }

    @Test("Titles are not empty")
    func titles() {
        for tab in PlayerInfoTab.allCases {
            #expect(!tab.title.isEmpty)
        }
    }
}

// MARK: - SearchResultType Tests

@Suite("SearchResultType Tests")
struct SearchResultTypeTests {

    @Test("All cases exist")
    func allCases() {
        let cases = SearchResultType.allCases
        #expect(cases.contains(.all))
        #expect(cases.contains(.videos))
        #expect(cases.contains(.channels))
        #expect(cases.contains(.playlists))
        #expect(cases.count == 4)
    }

    @Test("Titles are not empty")
    func titles() {
        for type in SearchResultType.allCases {
            #expect(!type.title.isEmpty)
        }
    }

    @Test("Identifiable id uses rawValue")
    func identifiableID() {
        for type in SearchResultType.allCases {
            #expect(type.id == type.rawValue)
        }
    }
}

// MARK: - CommentsLoadState Tests

@Suite("CommentsLoadState Tests")
struct CommentsLoadStateTests {

    @Test("All states are equatable")
    func equatable() {
        #expect(CommentsLoadState.idle == CommentsLoadState.idle)
        #expect(CommentsLoadState.loading == CommentsLoadState.loading)
        #expect(CommentsLoadState.loaded == CommentsLoadState.loaded)
        #expect(CommentsLoadState.loadingMore == CommentsLoadState.loadingMore)
        #expect(CommentsLoadState.disabled == CommentsLoadState.disabled)
        #expect(CommentsLoadState.error == CommentsLoadState.error)
    }

    @Test("Different states are not equal")
    func notEqual() {
        #expect(CommentsLoadState.idle != CommentsLoadState.loading)
        #expect(CommentsLoadState.loaded != CommentsLoadState.error)
        #expect(CommentsLoadState.loading != CommentsLoadState.loadingMore)
    }
}
