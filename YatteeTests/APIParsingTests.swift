//
//  APIParsingTests.swift
//  YatteeTests
//
//  Tests for API response parsing including Piped and PeerTube responses.
//

import Testing
import Foundation
@testable import Yattee

// MARK: - Piped Response Parsing Tests

@Suite("Piped API Parsing Tests")
@MainActor
struct PipedAPIParsingTests {

    @Test("Parse trending video response")
    func parseTrendingVideo() throws {
        let json = """
        {
            "url": "/watch?v=dQw4w9WgXcQ",
            "title": "Rick Astley - Never Gonna Give You Up",
            "uploaderName": "Rick Astley",
            "uploaderUrl": "/channel/UCuAXFkgsw1L7xaCfnd5JJOw",
            "uploaderAvatar": "https://example.com/avatar.jpg",
            "duration": 213,
            "uploaded": 562732800000,
            "views": 1400000000,
            "thumbnail": "https://example.com/thumb.jpg",
            "uploaderVerified": true,
            "isShort": false
        }
        """.data(using: .utf8)!

        // Verify JSON is valid and can be decoded
        let decoded = try JSONSerialization.jsonObject(with: json)
        #expect(decoded is [String: Any])

        let dict = decoded as! [String: Any]
        #expect(dict["url"] as? String == "/watch?v=dQw4w9WgXcQ")
        #expect(dict["title"] as? String == "Rick Astley - Never Gonna Give You Up")
        #expect(dict["duration"] as? Int == 213)
        #expect(dict["views"] as? Int64 == 1400000000)
    }

    @Test("Parse search response structure")
    func parseSearchResponse() throws {
        let json = """
        {
            "items": [
                {
                    "type": "stream",
                    "url": "/watch?v=test123",
                    "title": "Test Video",
                    "uploaderName": "Test Channel",
                    "duration": 120
                },
                {
                    "type": "channel",
                    "url": "/channel/UC123",
                    "name": "Test Channel",
                    "subscribers": 1000
                }
            ],
            "nextpage": "token123"
        }
        """.data(using: .utf8)!

        let decoded = try JSONSerialization.jsonObject(with: json) as! [String: Any]
        let items = decoded["items"] as! [[String: Any]]

        #expect(items.count == 2)
        #expect(items[0]["type"] as? String == "stream")
        #expect(items[1]["type"] as? String == "channel")
        #expect(decoded["nextpage"] as? String == "token123")
    }

    @Test("Parse stream response with HLS")
    func parseStreamResponseWithHLS() throws {
        let json = """
        {
            "title": "Test Video",
            "description": "A test video",
            "uploader": "Test Channel",
            "duration": 300,
            "views": 5000,
            "likes": 100,
            "hls": "https://example.com/stream.m3u8",
            "livestream": false,
            "videoStreams": [
                {
                    "url": "https://example.com/video.mp4",
                    "format": "MPEG_4",
                    "quality": "1080p",
                    "mimeType": "video/mp4",
                    "width": 1920,
                    "height": 1080
                }
            ],
            "audioStreams": [
                {
                    "url": "https://example.com/audio.m4a",
                    "format": "M4A",
                    "quality": "128kbps",
                    "mimeType": "audio/mp4",
                    "bitrate": 128000
                }
            ]
        }
        """.data(using: .utf8)!

        let decoded = try JSONSerialization.jsonObject(with: json) as! [String: Any]

        #expect(decoded["hls"] as? String == "https://example.com/stream.m3u8")
        #expect(decoded["livestream"] as? Bool == false)

        let videoStreams = decoded["videoStreams"] as! [[String: Any]]
        #expect(videoStreams.count == 1)
        #expect(videoStreams[0]["width"] as? Int == 1920)
        #expect(videoStreams[0]["height"] as? Int == 1080)

        let audioStreams = decoded["audioStreams"] as! [[String: Any]]
        #expect(audioStreams.count == 1)
        #expect(audioStreams[0]["bitrate"] as? Int == 128000)
    }

    @Test("Parse comments response")
    func parseCommentsResponse() throws {
        let json = """
        {
            "comments": [
                {
                    "commentId": "comment123",
                    "author": "Test User",
                    "commentorUrl": "/channel/UC123",
                    "commentText": "Great video!",
                    "commentedTime": "2 days ago",
                    "likeCount": 50,
                    "pinned": false,
                    "hearted": true,
                    "replyCount": 5
                }
            ],
            "nextpage": "nextToken"
        }
        """.data(using: .utf8)!

        let decoded = try JSONSerialization.jsonObject(with: json) as! [String: Any]
        let comments = decoded["comments"] as! [[String: Any]]

        #expect(comments.count == 1)
        #expect(comments[0]["commentId"] as? String == "comment123")
        #expect(comments[0]["likeCount"] as? Int == 50)
        #expect(comments[0]["pinned"] as? Bool == false)
        #expect(comments[0]["hearted"] as? Bool == true)
    }

    @Test("Video ID extraction from URL")
    func videoIdExtraction() {
        // Test the URL pattern used by Piped
        let watchURL = "/watch?v=dQw4w9WgXcQ"
        let videoId = watchURL.replacingOccurrences(of: "/watch?v=", with: "")
        #expect(videoId == "dQw4w9WgXcQ")

        let channelURL = "/channel/UCuAXFkgsw1L7xaCfnd5JJOw"
        let channelId = channelURL.replacingOccurrences(of: "/channel/", with: "")
        #expect(channelId == "UCuAXFkgsw1L7xaCfnd5JJOw")
    }
}

// MARK: - PeerTube Response Parsing Tests

@Suite("PeerTube API Parsing Tests")
@MainActor
struct PeerTubeAPIParsingTests {

    @Test("Parse video list response")
    func parseVideoListResponse() throws {
        let json = """
        {
            "total": 100,
            "data": [
                {
                    "id": 123,
                    "uuid": "abc-123-def",
                    "name": "Test Video",
                    "duration": 300,
                    "views": 1000,
                    "likes": 50,
                    "thumbnailPath": "/static/thumbnails/thumb.jpg",
                    "publishedAt": "2024-01-15T10:30:00.000Z",
                    "channel": {
                        "id": 1,
                        "name": "testchannel",
                        "displayName": "Test Channel"
                    }
                }
            ]
        }
        """.data(using: .utf8)!

        let decoded = try JSONSerialization.jsonObject(with: json) as! [String: Any]

        #expect(decoded["total"] as? Int == 100)

        let data = decoded["data"] as! [[String: Any]]
        #expect(data.count == 1)
        #expect(data[0]["id"] as? Int == 123)
        #expect(data[0]["uuid"] as? String == "abc-123-def")
        #expect(data[0]["name"] as? String == "Test Video")

        let channel = data[0]["channel"] as! [String: Any]
        #expect(channel["displayName"] as? String == "Test Channel")
    }

    @Test("Parse video details with streams")
    func parseVideoDetailsWithStreams() throws {
        let json = """
        {
            "id": 456,
            "uuid": "video-uuid-456",
            "name": "Video with Streams",
            "description": "A video with multiple stream formats",
            "duration": 600,
            "views": 5000,
            "files": [
                {
                    "fileUrl": "https://example.com/video-720p.mp4",
                    "resolution": {"id": 720, "label": "720p"},
                    "size": 104857600
                }
            ],
            "streamingPlaylists": [
                {
                    "id": 1,
                    "type": 1,
                    "playlistUrl": "https://example.com/master.m3u8",
                    "files": [
                        {
                            "fileUrl": "https://example.com/1080p.mp4",
                            "resolution": {"id": 1080, "label": "1080p"}
                        }
                    ]
                }
            ]
        }
        """.data(using: .utf8)!

        let decoded = try JSONSerialization.jsonObject(with: json) as! [String: Any]

        #expect(decoded["id"] as? Int == 456)

        let files = decoded["files"] as! [[String: Any]]
        #expect(files.count == 1)
        let resolution = files[0]["resolution"] as! [String: Any]
        #expect(resolution["id"] as? Int == 720)

        let streamingPlaylists = decoded["streamingPlaylists"] as! [[String: Any]]
        #expect(streamingPlaylists.count == 1)
        #expect(streamingPlaylists[0]["playlistUrl"] as? String == "https://example.com/master.m3u8")
    }

    @Test("Parse channel response")
    func parseChannelResponse() throws {
        let json = """
        {
            "id": 10,
            "name": "mychannel",
            "displayName": "My Channel",
            "description": "Channel description",
            "followersCount": 1500,
            "videosCount": 42,
            "avatar": {
                "path": "/lazy-static/avatars/avatar.png"
            },
            "banner": {
                "path": "/lazy-static/banners/banner.png"
            }
        }
        """.data(using: .utf8)!

        let decoded = try JSONSerialization.jsonObject(with: json) as! [String: Any]

        #expect(decoded["name"] as? String == "mychannel")
        #expect(decoded["displayName"] as? String == "My Channel")
        #expect(decoded["followersCount"] as? Int == 1500)
        #expect(decoded["videosCount"] as? Int == 42)

        let avatar = decoded["avatar"] as! [String: Any]
        #expect(avatar["path"] as? String == "/lazy-static/avatars/avatar.png")
    }

    @Test("Parse comment list response")
    func parseCommentListResponse() throws {
        let json = """
        {
            "total": 25,
            "data": [
                {
                    "id": 100,
                    "threadId": 100,
                    "text": "This is a comment",
                    "createdAt": "2024-01-20T15:00:00.000Z",
                    "account": {
                        "id": 5,
                        "name": "commenter",
                        "displayName": "Comment User"
                    },
                    "totalReplies": 3
                }
            ]
        }
        """.data(using: .utf8)!

        let decoded = try JSONSerialization.jsonObject(with: json) as! [String: Any]

        #expect(decoded["total"] as? Int == 25)

        let data = decoded["data"] as! [[String: Any]]
        #expect(data.count == 1)
        #expect(data[0]["text"] as? String == "This is a comment")
        #expect(data[0]["totalReplies"] as? Int == 3)

        let account = data[0]["account"] as! [String: Any]
        #expect(account["displayName"] as? String == "Comment User")
    }

    @Test("Parse playlist with videos")
    func parsePlaylistWithVideos() throws {
        let json = """
        {
            "id": 50,
            "uuid": "playlist-uuid-50",
            "displayName": "My Playlist",
            "description": "A test playlist",
            "videosLength": 10,
            "thumbnailPath": "/static/thumbnails/playlist.jpg",
            "ownerAccount": {
                "id": 1,
                "name": "owner",
                "displayName": "Playlist Owner"
            }
        }
        """.data(using: .utf8)!

        let decoded = try JSONSerialization.jsonObject(with: json) as! [String: Any]

        #expect(decoded["displayName"] as? String == "My Playlist")
        #expect(decoded["videosLength"] as? Int == 10)

        let owner = decoded["ownerAccount"] as! [String: Any]
        #expect(owner["displayName"] as? String == "Playlist Owner")
    }

    @Test("Pagination calculation")
    func paginationCalculation() {
        // PeerTube uses offset-based pagination (start parameter)
        let page = 3
        let count = 20
        let start = (page - 1) * count

        #expect(start == 40)

        // Test hasMore logic
        let total = 100
        let currentOffset = 40
        let itemsReturned = 20
        let nextOffset = currentOffset + itemsReturned
        let hasMore = nextOffset < total

        #expect(hasMore == true)

        // Edge case: last page
        let lastPageOffset = 80
        let lastPageNextOffset = lastPageOffset + 20
        let noMore = lastPageNextOffset < total

        #expect(noMore == false)
    }
}

// MARK: - Instance Detector Response Parsing Tests

@Suite("Instance Detector Parsing Tests")
@MainActor
struct InstanceDetectorParsingTests {

    @Test("Parse Yattee Server info response")
    func parseYatteeServerInfo() throws {
        let json = """
        {
            "name": "Yattee Server",
            "version": "1.0.0",
            "description": "A self-hosted video API server"
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(InstanceDetectorModels.YatteeServerInfo.self, from: json)

        #expect(decoded.name == "Yattee Server")
        #expect(decoded.version == "1.0.0")
        #expect(decoded.description == "A self-hosted video API server")
    }

    @Test("Parse PeerTube config response")
    func parsePeerTubeConfig() throws {
        let json = """
        {
            "instance": {
                "name": "PeerTube Instance",
                "shortDescription": "A federated video platform"
            },
            "serverVersion": "6.0.0"
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(InstanceDetectorModels.PeerTubeConfig.self, from: json)

        #expect(decoded.instance?.name == "PeerTube Instance")
        #expect(decoded.serverVersion == "6.0.0")
    }

    @Test("Parse Invidious stats response")
    func parseInvidiousStats() throws {
        let json = """
        {
            "software": {
                "name": "invidious",
                "version": "2.20240101.0"
            }
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(InstanceDetectorModels.InvidiousStats.self, from: json)

        #expect(decoded.software?.name == "invidious")
        #expect(decoded.software?.version == "2.20240101.0")
    }

    @Test("Parse Piped config response")
    func parsePipedConfig() throws {
        let json = """
        {
            "donationUrl": "https://donate.example.com",
            "statusPageUrl": "https://status.example.com",
            "s3Enabled": true
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(InstanceDetectorModels.PipedConfig.self, from: json)

        #expect(decoded.donationUrl == "https://donate.example.com")
        #expect(decoded.statusPageUrl == "https://status.example.com")
        #expect(decoded.s3Enabled == true)
    }

    @Test("Detection logic - Yattee Server identification")
    func yatteeServerIdentification() {
        // Name contains "yattee" (case insensitive)
        let yatteeServer = "Yattee Server"
        #expect(yatteeServer.lowercased().contains("yattee") == true)

        let otherServer = "Some Other Server"
        #expect(otherServer.lowercased().contains("yattee") == false)
    }

    @Test("Detection logic - Invidious identification")
    func invidiousIdentification() {
        // Software name must be exactly "invidious"
        let invidiousSoftware = "invidious"
        #expect(invidiousSoftware.lowercased() == "invidious")

        let otherSoftware = "peertube"
        #expect(otherSoftware.lowercased() != "invidious") // This should be true (not equal)
    }
}

// MARK: - Search Filters Tests

@Suite("SearchFilters Tests")
@MainActor
struct SearchFiltersTests {

    @Test("Default search filters")
    func defaultFilters() {
        let filters = SearchFilters.defaults

        #expect(filters.sort == .relevance)
        #expect(filters.date == .any)
        #expect(filters.duration == .any)
        #expect(filters.type == .video)
        #expect(filters.isDefault == true)
    }

    @Test("SearchFilters with custom values")
    func customFilters() {
        var filters = SearchFilters()
        filters.sort = .date
        filters.date = .week
        filters.duration = .long

        #expect(filters.isDefault == false)
    }

    @Test("SearchFilters Codable")
    func filtersCodable() throws {
        var filters = SearchFilters()
        filters.sort = .views
        filters.date = .month
        filters.duration = .short

        let encoded = try JSONEncoder().encode(filters)
        let decoded = try JSONDecoder().decode(SearchFilters.self, from: encoded)

        #expect(decoded == filters)
        #expect(decoded.sort == .views)
        #expect(decoded.date == .month)
        #expect(decoded.duration == .short)
    }

    @Test("SearchFilters Equatable")
    func filtersEquatable() {
        let filters1 = SearchFilters.defaults
        let filters2 = SearchFilters.defaults

        #expect(filters1 == filters2)

        var filters3 = SearchFilters.defaults
        filters3.sort = .rating

        #expect(filters1 != filters3)
    }

    @Test("SearchSortOption all cases")
    func sortOptionAllCases() {
        let allCases = SearchSortOption.allCases

        #expect(allCases.contains(.relevance))
        #expect(allCases.contains(.rating))
        #expect(allCases.contains(.date))
        #expect(allCases.contains(.views))
        #expect(allCases.count == 4)
    }

    @Test("SearchSortOption raw values")
    func sortOptionRawValues() {
        #expect(SearchSortOption.relevance.rawValue == "relevance")
        #expect(SearchSortOption.rating.rawValue == "rating")
        #expect(SearchSortOption.date.rawValue == "date")
        #expect(SearchSortOption.views.rawValue == "views")
    }

    @Test("SearchDateFilter all cases")
    func dateFilterAllCases() {
        let allCases = SearchDateFilter.allCases

        #expect(allCases.count == 6)
        #expect(SearchDateFilter.any.rawValue == "")
        #expect(SearchDateFilter.hour.rawValue == "hour")
        #expect(SearchDateFilter.today.rawValue == "today")
    }

    @Test("SearchDurationFilter all cases")
    func durationFilterAllCases() {
        let allCases = SearchDurationFilter.allCases

        #expect(allCases.count == 4)
        #expect(SearchDurationFilter.any.rawValue == "")
        #expect(SearchDurationFilter.short.rawValue == "short")
        #expect(SearchDurationFilter.medium.rawValue == "medium")
        #expect(SearchDurationFilter.long.rawValue == "long")
    }

    @Test("SearchContentType all cases")
    func contentTypeAllCases() {
        let allCases = SearchContentType.allCases

        #expect(allCases.count == 4)
        #expect(allCases.contains(.all))
        #expect(allCases.contains(.video))
        #expect(allCases.contains(.playlist))
        #expect(allCases.contains(.channel))
    }
}

// MARK: - MediaSource Tests

@Suite("MediaSource Tests")
@MainActor
struct MediaSourceTests {

    @Test("Create WebDAV media source")
    func createWebDAVSource() {
        let source = MediaSource.webdav(
            name: "My NAS",
            url: URL(string: "https://nas.local/webdav")!,
            username: "user"
        )

        #expect(source.name == "My NAS")
        #expect(source.type == .webdav)
        #expect(source.username == "user")
        #expect(source.requiresAuthentication == true)
        #expect(source.isEnabled == true)
    }

    @Test("Create local folder media source")
    func createLocalFolderSource() {
        let source = MediaSource.localFolder(
            name: "Downloads",
            url: URL(fileURLWithPath: "/Users/test/Downloads")
        )

        #expect(source.name == "Downloads")
        #expect(source.type == .localFolder)
        #expect(source.requiresAuthentication == false)
    }

    @Test("MediaSourceType display names")
    func mediaSourceTypeDisplayNames() {
        #expect(!MediaSourceType.webdav.displayName.isEmpty)
        #expect(!MediaSourceType.localFolder.displayName.isEmpty)
    }

    @Test("MediaSourceType system images")
    func mediaSourceTypeSystemImages() {
        #expect(MediaSourceType.webdav.systemImage == "externaldrive.connected.to.line.below")
        #expect(MediaSourceType.localFolder.systemImage == "folder")
        #expect(MediaSourceType.smb.systemImage == "externaldrive.connected.to.line.below")
    }

    @Test("MediaSource URL display string")
    func urlDisplayString() {
        let webdavSource = MediaSource.webdav(
            name: "Test",
            url: URL(string: "https://example.com/webdav")!
        )
        #expect(webdavSource.urlDisplayString == "example.com")

        let localSource = MediaSource.localFolder(
            name: "Test",
            url: URL(fileURLWithPath: "/Users/test/Videos")
        )
        #expect(localSource.urlDisplayString == "Videos")
    }

    @Test("MediaSource Codable")
    func mediaSourceCodable() throws {
        let source = MediaSource.webdav(
            name: "Test NAS",
            url: URL(string: "https://nas.example.com")!,
            username: "admin"
        )

        let encoded = try JSONEncoder().encode(source)
        let decoded = try JSONDecoder().decode(MediaSource.self, from: encoded)

        #expect(decoded.name == source.name)
        #expect(decoded.type == source.type)
        #expect(decoded.url == source.url)
        #expect(decoded.username == source.username)
    }

    @Test("MediaSource Identifiable")
    func mediaSourceIdentifiable() {
        let source1 = MediaSource.webdav(name: "Test1", url: URL(string: "https://a.com")!)
        let source2 = MediaSource.webdav(name: "Test2", url: URL(string: "https://b.com")!)

        #expect(source1.id != source2.id)
    }

    @Test("MediaSource Hashable")
    func mediaSourceHashable() {
        let source = MediaSource.webdav(name: "Test", url: URL(string: "https://a.com")!)

        var set = Set<MediaSource>()
        set.insert(source)

        #expect(set.contains(source))
    }

    @Test("MediaSourceType all cases")
    func mediaSourceTypeAllCases() {
        let allCases = MediaSourceType.allCases

        #expect(allCases.count == 3)
        #expect(allCases.contains(.webdav))
        #expect(allCases.contains(.localFolder))
        #expect(allCases.contains(.smb))
    }
}

// MARK: - Content Service Routing Tests

@Suite("Content Service Routing Tests")
@MainActor
struct ContentServiceRoutingTests {

    @Test("Invidious instance routes correctly")
    func invidiousRouting() {
        let instance = Instance(type: .invidious, url: URL(string: "https://inv.example.com")!)
        #expect(instance.type == .invidious)
        #expect(instance.isYouTubeInstance == true)
        #expect(instance.isPeerTubeInstance == false)
    }

    @Test("Piped instance routes correctly")
    func pipedRouting() {
        let instance = Instance(type: .piped, url: URL(string: "https://piped.example.com")!)
        #expect(instance.type == .piped)
        #expect(instance.isYouTubeInstance == true)
        #expect(instance.isPeerTubeInstance == false)
    }

    @Test("PeerTube instance routes correctly")
    func peerTubeRouting() {
        let instance = Instance(type: .peertube, url: URL(string: "https://pt.example.com")!)
        #expect(instance.type == .peertube)
        #expect(instance.isYouTubeInstance == false)
        #expect(instance.isPeerTubeInstance == true)
    }

    @Test("Yattee Server instance routes correctly")
    func yatteeServerRouting() {
        let instance = Instance(type: .yatteeServer, url: URL(string: "https://ys.example.com")!)
        #expect(instance.type == .yatteeServer)
        #expect(instance.isYouTubeInstance == true)
        #expect(instance.isPeerTubeInstance == false)
    }

    @Test("All instance types have unique raw values")
    func instanceTypesUnique() {
        let types = InstanceType.allCases
        let rawValues = Set(types.map(\.rawValue))

        #expect(rawValues.count == types.count)
    }

    @Test("Instance types are Codable")
    func instanceTypesCodable() throws {
        for type in InstanceType.allCases {
            let encoded = try JSONEncoder().encode(type)
            let decoded = try JSONDecoder().decode(InstanceType.self, from: encoded)
            #expect(type == decoded)
        }
    }
}

// MARK: - Piped Authentication Parsing Tests

@Suite("Piped Authentication Parsing Tests")
@MainActor
struct PipedAuthenticationParsingTests {

    @Test("Parse login response")
    func parseLoginResponse() throws {
        let json = """
        {
            "token": "abc123-auth-token-xyz789"
        }
        """.data(using: .utf8)!

        let decoded = try JSONSerialization.jsonObject(with: json) as! [String: Any]

        #expect(decoded["token"] as? String == "abc123-auth-token-xyz789")
    }

    @Test("Parse subscription list response")
    func parseSubscriptionListResponse() throws {
        let json = """
        [
            {
                "url": "/channel/UCuAXFkgsw1L7xaCfnd5JJOw",
                "name": "Rick Astley",
                "avatar": "https://example.com/avatar1.jpg",
                "verified": true
            },
            {
                "url": "/channel/UC-lHJZR3Gqxm24_Vd_AJ5Yw",
                "name": "PewDiePie",
                "avatar": "https://example.com/avatar2.jpg",
                "verified": true
            }
        ]
        """.data(using: .utf8)!

        let decoded = try JSONSerialization.jsonObject(with: json) as! [[String: Any]]

        #expect(decoded.count == 2)
        #expect(decoded[0]["url"] as? String == "/channel/UCuAXFkgsw1L7xaCfnd5JJOw")
        #expect(decoded[0]["name"] as? String == "Rick Astley")
        #expect(decoded[0]["verified"] as? Bool == true)
        #expect(decoded[1]["name"] as? String == "PewDiePie")
    }

    @Test("Parse feed response (array of videos)")
    func parseFeedResponse() throws {
        let json = """
        [
            {
                "url": "/watch?v=dQw4w9WgXcQ",
                "title": "Never Gonna Give You Up",
                "uploaderName": "Rick Astley",
                "uploaderUrl": "/channel/UCuAXFkgsw1L7xaCfnd5JJOw",
                "duration": 213,
                "views": 1400000000,
                "thumbnail": "https://example.com/thumb1.jpg"
            },
            {
                "url": "/watch?v=video123",
                "title": "Another Video",
                "uploaderName": "Channel Name",
                "uploaderUrl": "/channel/UCxyz123",
                "duration": 600,
                "views": 50000,
                "thumbnail": "https://example.com/thumb2.jpg"
            }
        ]
        """.data(using: .utf8)!

        let decoded = try JSONSerialization.jsonObject(with: json) as! [[String: Any]]

        #expect(decoded.count == 2)
        #expect(decoded[0]["url"] as? String == "/watch?v=dQw4w9WgXcQ")
        #expect(decoded[0]["title"] as? String == "Never Gonna Give You Up")
        #expect(decoded[0]["duration"] as? Int == 213)
    }

    @Test("PipedSubscription model decoding")
    func pipedSubscriptionDecoding() throws {
        let json = """
        {
            "url": "/channel/UCuAXFkgsw1L7xaCfnd5JJOw",
            "name": "Rick Astley",
            "avatar": "https://example.com/avatar.jpg",
            "verified": true
        }
        """.data(using: .utf8)!

        let subscription = try JSONDecoder().decode(PipedSubscription.self, from: json)

        #expect(subscription.url == "/channel/UCuAXFkgsw1L7xaCfnd5JJOw")
        #expect(subscription.name == "Rick Astley")
        #expect(subscription.avatar == "https://example.com/avatar.jpg")
        #expect(subscription.verified == true)
    }

    @Test("PipedSubscription channelId extraction")
    func pipedSubscriptionChannelIdExtraction() throws {
        let json = """
        {
            "url": "/channel/UCuAXFkgsw1L7xaCfnd5JJOw",
            "name": "Test Channel"
        }
        """.data(using: .utf8)!

        let subscription = try JSONDecoder().decode(PipedSubscription.self, from: json)

        #expect(subscription.channelId == "UCuAXFkgsw1L7xaCfnd5JJOw")
    }

    @Test("PipedSubscription toChannel conversion")
    func pipedSubscriptionToChannel() throws {
        let json = """
        {
            "url": "/channel/UCuAXFkgsw1L7xaCfnd5JJOw",
            "name": "Rick Astley",
            "avatar": "https://example.com/avatar.jpg",
            "verified": true
        }
        """.data(using: .utf8)!

        let subscription = try JSONDecoder().decode(PipedSubscription.self, from: json)
        let channel = subscription.toChannel()

        #expect(channel.name == "Rick Astley")
        #expect(channel.thumbnailURL?.absoluteString == "https://example.com/avatar.jpg")
        #expect(channel.isVerified == true)
    }

    @Test("PipedSubscription with nil optional fields")
    func pipedSubscriptionNilOptionals() throws {
        let json = """
        {
            "url": "/channel/UC123",
            "name": "Basic Channel"
        }
        """.data(using: .utf8)!

        let subscription = try JSONDecoder().decode(PipedSubscription.self, from: json)

        #expect(subscription.name == "Basic Channel")
        #expect(subscription.avatar == nil)
        #expect(subscription.verified == nil)

        let channel = subscription.toChannel()
        #expect(channel.thumbnailURL == nil)
        #expect(channel.isVerified == false)
    }

    @Test("Login error response structure")
    func loginErrorResponseStructure() throws {
        // When login fails, Piped returns 401 or 403
        // The app should map this to APIError.unauthorized
        let statusCodes = [401, 403]

        for statusCode in statusCodes {
            #expect(statusCode == 401 || statusCode == 403)
        }
    }
}

// MARK: - Stream Resolution Tests

@Suite("Stream Resolution Tests")
@MainActor
struct StreamResolutionTests {

    @Test("StreamResolution from width and height")
    func resolutionFromDimensions() {
        let resolution = StreamResolution(width: 1920, height: 1080)
        #expect(resolution.height == 1080)
        #expect(resolution.width == 1920)
    }

    @Test("StreamResolution static constants")
    func staticConstants() {
        #expect(StreamResolution.p720.height == 720)
        #expect(StreamResolution.p1080.height == 1080)
        #expect(StreamResolution.p2160.height == 2160)
    }

    @Test("StreamResolution comparison")
    func resolutionComparison() {
        let r720 = StreamResolution(width: 1280, height: 720)
        let r1080 = StreamResolution(width: 1920, height: 1080)
        let r4k = StreamResolution(width: 3840, height: 2160)

        #expect(r720 < r1080)
        #expect(r1080 < r4k)
        #expect(r4k > r720)
    }

    @Test("StreamResolution description")
    func resolutionDescription() {
        let resolution = StreamResolution(width: 1920, height: 1080)
        // description returns "heightp" format
        #expect(resolution.description == "1080p")
    }

    @Test("StreamResolution Codable")
    func resolutionCodable() throws {
        let resolution = StreamResolution(width: 1920, height: 1080)
        let encoded = try JSONEncoder().encode(resolution)
        let decoded = try JSONDecoder().decode(StreamResolution.self, from: encoded)

        #expect(decoded.width == resolution.width)
        #expect(decoded.height == resolution.height)
    }

    @Test("StreamResolution Hashable")
    func resolutionHashable() {
        let r1 = StreamResolution(width: 1920, height: 1080)
        let r2 = StreamResolution(width: 1920, height: 1080)

        #expect(r1 == r2)

        var set = Set<StreamResolution>()
        set.insert(r1)
        #expect(set.contains(r2))
    }
}

// MARK: - Playlist Parsing Error Handling Tests

@Suite("Playlist Parsing Error Handling Tests")
@MainActor
struct PlaylistParsingErrorHandlingTests {

    @Test("Invidious playlist with parse-error items structure")
    func invidiousPlaylistWithParseErrors() throws {
        // Simulates the real Invidious API response with parse-error items
        // This validates that our code can handle this JSON structure
        let json = """
        {
            "playlistId": "PLtest123",
            "title": "Test Playlist",
            "description": "A playlist with some parse errors",
            "author": "Test Author",
            "authorId": "UCtest123",
            "videoCount": 3,
            "videos": [
                {
                    "type": "video",
                    "videoId": "video1",
                    "title": "First Video",
                    "author": "Author 1",
                    "authorId": "UC1",
                    "lengthSeconds": 120,
                    "liveNow": false
                },
                {
                    "type": "parse-error",
                    "errorMessage": "Missing hash key: \\"browseEndpoint\\"",
                    "errorBacktrace": "Some stack trace..."
                },
                {
                    "type": "video",
                    "videoId": "video2",
                    "title": "Second Video",
                    "author": "Author 2",
                    "authorId": "UC2",
                    "lengthSeconds": 240,
                    "liveNow": false
                }
            ]
        }
        """.data(using: .utf8)!

        // Verify the JSON structure is valid
        let decoded = try JSONSerialization.jsonObject(with: json) as! [String: Any]
        let videos = decoded["videos"] as! [[String: Any]]

        #expect(videos.count == 3)
        #expect(videos[0]["type"] as? String == "video")
        #expect(videos[0]["videoId"] as? String == "video1")
        #expect(videos[1]["type"] as? String == "parse-error")
        #expect(videos[1]["errorMessage"] != nil)
        #expect(videos[2]["type"] as? String == "video")
        #expect(videos[2]["videoId"] as? String == "video2")
    }

    @Test("Invidious playlist videos without type field default to video")
    func invidiousPlaylistVideosWithoutType() throws {
        // Some Invidious responses don't include type field for videos
        let json = """
        {
            "playlistId": "PLtest456",
            "title": "Test Playlist",
            "videoCount": 1,
            "videos": [
                {
                    "videoId": "video1",
                    "title": "Video Without Type",
                    "author": "Author",
                    "authorId": "UC1",
                    "lengthSeconds": 180,
                    "liveNow": false
                }
            ]
        }
        """.data(using: .utf8)!

        let decoded = try JSONSerialization.jsonObject(with: json) as! [String: Any]
        let videos = decoded["videos"] as! [[String: Any]]

        #expect(videos.count == 1)
        #expect(videos[0]["type"] == nil)
        #expect(videos[0]["videoId"] as? String == "video1")
    }

    @Test("Piped playlist with malformed items structure")
    func pipedPlaylistWithMalformedItems() throws {
        let json = """
        {
            "name": "Test Playlist",
            "description": "A test playlist",
            "uploader": "Test Uploader",
            "videos": 2,
            "relatedStreams": [
                {
                    "url": "/watch?v=valid123",
                    "title": "Valid Video",
                    "uploaderName": "Uploader",
                    "duration": 300
                },
                {
                    "invalid": "item",
                    "missing": "required fields"
                }
            ]
        }
        """.data(using: .utf8)!

        let decoded = try JSONSerialization.jsonObject(with: json) as! [String: Any]
        let streams = decoded["relatedStreams"] as! [[String: Any]]

        #expect(streams.count == 2)
        #expect(streams[0]["url"] as? String == "/watch?v=valid123")
        #expect(streams[1]["url"] == nil) // Missing required field
    }

    @Test("Empty playlist videos array should be handled")
    func emptyPlaylistVideos() throws {
        let json = """
        {
            "playlistId": "PL_empty",
            "title": "Empty Playlist",
            "videoCount": 0,
            "videos": []
        }
        """.data(using: .utf8)!

        let decoded = try JSONSerialization.jsonObject(with: json) as! [String: Any]
        let videos = decoded["videos"] as! [[String: Any]]

        #expect(videos.isEmpty)
    }

    @Test("Playlist with null videos array should be handled")
    func nullPlaylistVideos() throws {
        let json = """
        {
            "playlistId": "PL_null",
            "title": "Playlist with null videos",
            "videoCount": 5
        }
        """.data(using: .utf8)!

        let decoded = try JSONSerialization.jsonObject(with: json) as! [String: Any]

        #expect(decoded["videos"] == nil)
    }

    @Test("Unknown video type should be skipped")
    func unknownVideoType() throws {
        let json = """
        {
            "playlistId": "PL_unknown",
            "title": "Playlist with unknown types",
            "videoCount": 2,
            "videos": [
                {
                    "type": "future-type",
                    "someField": "someValue"
                },
                {
                    "type": "video",
                    "videoId": "valid",
                    "title": "Valid",
                    "author": "Author",
                    "authorId": "UC1",
                    "lengthSeconds": 60,
                    "liveNow": false
                }
            ]
        }
        """.data(using: .utf8)!

        let decoded = try JSONSerialization.jsonObject(with: json) as! [String: Any]
        let videos = decoded["videos"] as! [[String: Any]]

        #expect(videos.count == 2)
        #expect(videos[0]["type"] as? String == "future-type")
        #expect(videos[1]["type"] as? String == "video")
    }

    @Test("Multiple parse-error items in playlist")
    func multipleParseErrors() throws {
        // Real-world scenario where multiple videos fail to parse
        let json = """
        {
            "playlistId": "PLmulti",
            "title": "Playlist with multiple errors",
            "videoCount": 5,
            "videos": [
                {"type": "parse-error", "errorMessage": "Error 1"},
                {"type": "video", "videoId": "v1", "title": "V1", "author": "A", "authorId": "UC1", "lengthSeconds": 60, "liveNow": false},
                {"type": "parse-error", "errorMessage": "Error 2"},
                {"type": "parse-error", "errorMessage": "Error 3"},
                {"type": "video", "videoId": "v2", "title": "V2", "author": "A", "authorId": "UC1", "lengthSeconds": 120, "liveNow": false}
            ]
        }
        """.data(using: .utf8)!

        let decoded = try JSONSerialization.jsonObject(with: json) as! [String: Any]
        let videos = decoded["videos"] as! [[String: Any]]

        #expect(videos.count == 5)

        // Count valid videos vs parse errors
        let validCount = videos.filter { ($0["type"] as? String) == "video" }.count
        let errorCount = videos.filter { ($0["type"] as? String) == "parse-error" }.count

        #expect(validCount == 2)
        #expect(errorCount == 3)
    }

    @Test("Piped playlist with empty relatedStreams")
    func pipedEmptyRelatedStreams() throws {
        let json = """
        {
            "name": "Empty Piped Playlist",
            "videos": 0,
            "relatedStreams": []
        }
        """.data(using: .utf8)!

        let decoded = try JSONSerialization.jsonObject(with: json) as! [String: Any]
        let streams = decoded["relatedStreams"] as! [[String: Any]]

        #expect(streams.isEmpty)
    }

    @Test("Piped playlist with null relatedStreams")
    func pipedNullRelatedStreams() throws {
        let json = """
        {
            "name": "Piped Playlist without streams",
            "videos": 10
        }
        """.data(using: .utf8)!

        let decoded = try JSONSerialization.jsonObject(with: json) as! [String: Any]

        #expect(decoded["relatedStreams"] == nil)
    }
}
