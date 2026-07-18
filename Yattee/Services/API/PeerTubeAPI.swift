//
//  PeerTubeAPI.swift
//  Yattee
//
//  PeerTube API implementation.
//  API Documentation: https://docs.joinpeertube.org/api-rest-reference.html
//

@preconcurrency import Foundation

/// PeerTube API client for federated video content.
actor PeerTubeAPI: InstanceAPI {
    private let httpClient: HTTPClient

    init(httpClient: HTTPClient) {
        self.httpClient = httpClient
    }

    // MARK: - InstanceAPI

    func trending(instance: Instance) async throws -> [Video] {
        let endpoint = GenericEndpoint.get("/api/v1/videos", query: [
            "sort": "-trending",
            "count": "20"
        ])
        let response: PeerTubeVideoList = try await httpClient.fetch(endpoint, baseURL: instance.url)
        return response.data.map { $0.toVideo(instanceURL: instance.url) }
    }

    func popular(instance: Instance) async throws -> [Video] {
        let endpoint = GenericEndpoint.get("/api/v1/videos", query: [
            "sort": "-views",
            "count": "20"
        ])
        let response: PeerTubeVideoList = try await httpClient.fetch(endpoint, baseURL: instance.url)
        return response.data.map { $0.toVideo(instanceURL: instance.url) }
    }

    func search(query: String, instance: Instance, page: Int, filters: SearchFilters) async throws -> SearchResult {
        let start = (page - 1) * 20
        let endpoint = GenericEndpoint.get("/api/v1/search/videos", query: [
            "search": query,
            "start": String(start),
            "count": "20"
        ])
        let response: PeerTubeVideoList = try await httpClient.fetch(endpoint, baseURL: instance.url)

        let videos = response.data.map { $0.toVideo(instanceURL: instance.url) }
        let hasMore = start + videos.count < response.total

        return SearchResult(
            videos: videos,
            channels: [],
            playlists: [],
            orderedItems: videos.map { .video($0) },
            nextPage: hasMore ? page + 1 : nil
        )
    }

    func video(id: String, instance: Instance) async throws -> Video {
        let endpoint = GenericEndpoint.get("/api/v1/videos/\(id)")
        let response: PeerTubeVideoDetails = try await httpClient.fetch(endpoint, baseURL: instance.url)
        return response.toVideo(instanceURL: instance.url)
    }

    func channel(id: String, instance: Instance) async throws -> Channel {
        let endpoint = GenericEndpoint.get("/api/v1/video-channels/\(id)")
        let response: PeerTubeChannel = try await httpClient.fetch(endpoint, baseURL: instance.url)
        return response.toChannel(instanceURL: instance.url)
    }

    func channelVideos(id: String, instance: Instance, continuation: String?) async throws -> ChannelVideosPage {
        let pageSize = 20
        let start = continuation.flatMap { Int($0) } ?? 0
        let endpoint = GenericEndpoint.get("/api/v1/video-channels/\(id)/videos", query: [
            "start": String(start),
            "count": String(pageSize)
        ])
        let response: PeerTubeVideoList = try await httpClient.fetch(endpoint, baseURL: instance.url)
        let videos = response.data.map { $0.toVideo(instanceURL: instance.url) }
        // If we got a full page, there might be more
        let nextContinuation = videos.count == pageSize ? String(start + pageSize) : nil
        return ChannelVideosPage(videos: videos, continuation: nextContinuation)
    }

    func playlist(id: String, instance: Instance) async throws -> Playlist {
        let endpoint = GenericEndpoint.get("/api/v1/video-playlists/\(id)")
        let response: PeerTubePlaylist = try await httpClient.fetch(endpoint, baseURL: instance.url)

        // Fetch playlist videos
        let videosEndpoint = GenericEndpoint.get("/api/v1/video-playlists/\(id)/videos")
        let videosResponse: PeerTubePlaylistVideos = try await httpClient.fetch(videosEndpoint, baseURL: instance.url)

        return response.toPlaylist(instanceURL: instance.url, videos: videosResponse.data)
    }

    func comments(videoID: String, instance: Instance, continuation: String?) async throws -> CommentsPage {
        // PeerTube uses offset-based pagination, continuation is the offset as string
        let offset = continuation.flatMap { Int($0) } ?? 0
        let count = 20
        let endpoint = GenericEndpoint.get("/api/v1/videos/\(videoID)/comment-threads", query: [
            "start": String(offset),
            "count": String(count)
        ])
        let response: PeerTubeCommentList = try await httpClient.fetch(endpoint, baseURL: instance.url)
        let nextOffset = offset + response.data.count
        let hasMore = nextOffset < response.total
        return CommentsPage(
            comments: response.data.map { $0.toComment(instanceURL: instance.url) },
            continuation: hasMore ? String(nextOffset) : nil
        )
    }

    func streams(videoID: String, instance: Instance) async throws -> [Stream] {
        let endpoint = GenericEndpoint.get("/api/v1/videos/\(videoID)")
        let response: PeerTubeVideoDetails = try await httpClient.fetch(endpoint, baseURL: instance.url)
        return response.toStreams(instanceURL: instance.url)
    }
}

// MARK: - PeerTube Response Models

private struct PeerTubeVideoList: Decodable, Sendable {
    let total: Int
    let data: [PeerTubeVideo]
}

private struct PeerTubeVideo: Decodable, Sendable {
    let id: Int
    let uuid: String
    let shortUUID: String?
    let name: String
    let description: String?
    let duration: Int
    let views: Int?
    let likes: Int?
    let dislikes: Int?
    let thumbnailPath: String?
    let previewPath: String?
    let publishedAt: String?
    let originallyPublishedAt: String?
    let createdAt: String?
    let channel: PeerTubeVideoChannel?
    let account: PeerTubeAccount?
    let isLive: Bool?

    private enum CodingKeys: String, CodingKey {
        case id, uuid, name, description, duration, views, likes, dislikes, channel, account
        case shortUUID, thumbnailPath, previewPath, publishedAt, originallyPublishedAt, createdAt, isLive
    }

    nonisolated func toVideo(instanceURL: URL) -> Video {
        let publishDate = publishedAt.flatMap { ISO8601DateFormatter().date(from: $0) }

        var thumbnails: [Thumbnail] = []
        if let thumbnailPath {
            let thumbURL = instanceURL.appendingPathComponent(thumbnailPath)
            thumbnails.append(Thumbnail(url: thumbURL, quality: .medium))
        }
        if let previewPath {
            let previewURL = instanceURL.appendingPathComponent(previewPath)
            thumbnails.append(Thumbnail(url: previewURL, quality: .high))
        }

        // For federated channels, use the channel's actual host instance
        let channelInstance: URL
        if let channelHost = channel?.host,
           let hostURL = URL(string: "https://\(channelHost)"),
           hostURL.host != instanceURL.host {
            channelInstance = hostURL
        } else {
            channelInstance = instanceURL
        }

        return Video(
            id: .federated(String(id), instance: instanceURL, uuid: uuid),
            title: name,
            description: description,
            author: Author(
                id: channel?.name ?? account?.name ?? "",
                name: channel?.displayName ?? account?.displayName ?? "",
                thumbnailURL: (channel?.avatar ?? account?.avatar)
                    .flatMap { instanceURL.appendingPathComponent($0.path) },
                instance: channelInstance
            ),
            duration: TimeInterval(duration),
            publishedAt: publishDate,
            publishedText: nil,
            viewCount: views,
            likeCount: likes,
            thumbnails: thumbnails,
            isLive: isLive ?? false,
            isUpcoming: false,
            scheduledStartTime: nil
        )
    }
}

private struct PeerTubeVideoDetails: Decodable, Sendable {
    let id: Int
    let uuid: String
    let shortUUID: String?
    let name: String
    let description: String?
    let duration: Int
    let views: Int?
    let likes: Int?
    let dislikes: Int?
    let thumbnailPath: String?
    let previewPath: String?
    let publishedAt: String?
    let channel: PeerTubeVideoChannel?
    let account: PeerTubeAccount?
    let isLive: Bool?
    let files: [PeerTubeVideoFile]?
    let streamingPlaylists: [PeerTubeStreamingPlaylist]?

    private enum CodingKeys: String, CodingKey {
        case id, uuid, name, description, duration, views, likes, dislikes, channel, account, files
        case shortUUID, thumbnailPath, previewPath, publishedAt, isLive, streamingPlaylists
    }

    nonisolated func toVideo(instanceURL: URL) -> Video {
        let publishDate = publishedAt.flatMap { ISO8601DateFormatter().date(from: $0) }

        var thumbnails: [Thumbnail] = []
        if let thumbnailPath {
            let thumbURL = instanceURL.appendingPathComponent(thumbnailPath)
            thumbnails.append(Thumbnail(url: thumbURL, quality: .medium))
        }
        if let previewPath {
            let previewURL = instanceURL.appendingPathComponent(previewPath)
            thumbnails.append(Thumbnail(url: previewURL, quality: .high))
        }

        // For federated channels, use the channel's actual host instance
        let channelInstance: URL
        if let channelHost = channel?.host,
           let hostURL = URL(string: "https://\(channelHost)"),
           hostURL.host != instanceURL.host {
            channelInstance = hostURL
        } else {
            channelInstance = instanceURL
        }

        return Video(
            id: .federated(String(id), instance: instanceURL, uuid: uuid),
            title: name,
            description: description,
            author: Author(
                id: channel?.name ?? account?.name ?? "",
                name: channel?.displayName ?? account?.displayName ?? "",
                thumbnailURL: (channel?.avatar ?? account?.avatar)
                    .flatMap { instanceURL.appendingPathComponent($0.path) },
                instance: channelInstance
            ),
            duration: TimeInterval(duration),
            publishedAt: publishDate,
            publishedText: nil,
            viewCount: views,
            likeCount: likes,
            thumbnails: thumbnails,
            isLive: isLive ?? false,
            isUpcoming: false,
            scheduledStartTime: nil
        )
    }

    nonisolated func toStreams(instanceURL: URL) -> [Stream] {
        var streams: [Stream] = []

        // Add HLS streams
        if let streamingPlaylists {
            for playlist in streamingPlaylists {
                if let playlistUrl = URL(string: playlist.playlistUrl) {
                    streams.append(Stream(
                        url: playlistUrl,
                        resolution: nil,
                        format: "hls",
                        isLive: isLive ?? false,
                        mimeType: "application/x-mpegURL"
                    ))
                }

                // Add individual resolution files from HLS
                for file in playlist.files ?? [] {
                    if let fileUrl = URL(string: file.fileUrl) {
                        streams.append(Stream(
                            url: fileUrl,
                            resolution: file.resolution.flatMap {
                                StreamResolution(width: 0, height: $0.id)
                            },
                            format: "mp4",
                            audioCodec: "aac",  // Mark as muxed (PeerTube MP4s contain audio)
                            fileSize: file.size,
                            mimeType: file.metadataUrl.flatMap { _ in "video/mp4" }
                        ))
                    }
                }
            }
        }

        // Add direct file downloads
        if let files {
            for file in files {
                if let fileUrl = URL(string: file.fileUrl) {
                    streams.append(Stream(
                        url: fileUrl,
                        resolution: file.resolution.flatMap {
                            StreamResolution(width: 0, height: $0.id)
                        },
                        format: "mp4",
                        audioCodec: "aac",  // Mark as muxed (PeerTube MP4s contain audio)
                        fileSize: file.size,
                        mimeType: "video/mp4"
                    ))
                }
            }
        }

        return streams
    }
}

private struct PeerTubeVideoFile: Decodable, Sendable {
    let fileUrl: String
    let fileDownloadUrl: String?
    let resolution: PeerTubeResolution?
    let size: Int64?
    let fps: Int?
    let metadataUrl: String?

    private enum CodingKeys: String, CodingKey {
        case resolution, size, fps
        case fileUrl, fileDownloadUrl, metadataUrl
    }
}

private struct PeerTubeResolution: Decodable, Sendable {
    let id: Int
    let label: String
}

private struct PeerTubeStreamingPlaylist: Decodable, Sendable {
    let id: Int
    let type: Int
    let playlistUrl: String
    let files: [PeerTubeVideoFile]?

    private enum CodingKeys: String, CodingKey {
        case id, type, files
        case playlistUrl
    }
}

private struct PeerTubeVideoChannel: Decodable, Sendable {
    let id: Int
    let name: String
    let displayName: String
    let description: String?
    let url: String?
    let host: String?
    let avatar: PeerTubeAvatar?
    let banner: PeerTubeAvatar?
    let followersCount: Int?

    private enum CodingKeys: String, CodingKey {
        case id, name, description, url, host, avatar, banner
        case displayName, followersCount
    }
}

private struct PeerTubeAccount: Decodable, Sendable {
    let id: Int
    let name: String
    let displayName: String
    let description: String?
    let url: String?
    let host: String?
    let avatar: PeerTubeAvatar?
    let followersCount: Int?

    private enum CodingKeys: String, CodingKey {
        case id, name, description, url, host, avatar
        case displayName, followersCount
    }
}

private struct PeerTubeAvatar: Decodable, Sendable {
    let path: String
    let width: Int?
    let createdAt: String?
    let updatedAt: String?

    private enum CodingKeys: String, CodingKey {
        case path, width
        case createdAt, updatedAt
    }
}

private struct PeerTubeChannel: Decodable, Sendable {
    let id: Int
    let name: String
    let displayName: String
    let description: String?
    let url: String?
    let host: String?
    let avatar: PeerTubeAvatar?
    let banner: PeerTubeAvatar?
    let followersCount: Int?
    let videosCount: Int?

    private enum CodingKeys: String, CodingKey {
        case id, name, description, url, host, avatar, banner
        case displayName, followersCount, videosCount
    }

    nonisolated func toChannel(instanceURL: URL) -> Channel {
        Channel(
            id: .federated(name, instance: instanceURL),
            name: displayName,
            description: description,
            subscriberCount: followersCount,
            videoCount: videosCount,
            thumbnailURL: avatar.map { instanceURL.appendingPathComponent($0.path) },
            bannerURL: banner.map { instanceURL.appendingPathComponent($0.path) }
        )
    }
}

private struct PeerTubePlaylist: Decodable, Sendable {
    let id: Int
    let uuid: String
    let displayName: String
    let description: String?
    let thumbnailPath: String?
    let videosLength: Int
    let ownerAccount: PeerTubeAccount?
    let videoChannel: PeerTubeVideoChannel?

    private enum CodingKeys: String, CodingKey {
        case id, uuid, description
        case displayName, thumbnailPath, videosLength, ownerAccount, videoChannel
    }

    nonisolated func toPlaylist(instanceURL: URL, videos: [PeerTubePlaylistVideo]) -> Playlist {
        Playlist(
            id: .federated(String(id), instance: instanceURL),
            title: displayName,
            description: description,
            author: ownerAccount.map {
                Author(
                    id: $0.name,
                    name: $0.displayName,
                    thumbnailURL: $0.avatar.map { instanceURL.appendingPathComponent($0.path) },
                    instance: instanceURL
                )
            },
            videoCount: videosLength,
            thumbnailURL: thumbnailPath.map { instanceURL.appendingPathComponent($0) },
            videos: videos.map { $0.video.toVideo(instanceURL: instanceURL) }
        )
    }
}

private struct PeerTubePlaylistVideos: Decodable, Sendable {
    let total: Int
    let data: [PeerTubePlaylistVideo]
}

private struct PeerTubePlaylistVideo: Decodable, Sendable {
    let id: Int
    let video: PeerTubeVideo
    let position: Int
    let startTimestamp: Int?
    let stopTimestamp: Int?

    private enum CodingKeys: String, CodingKey {
        case id, video, position
        case startTimestamp, stopTimestamp
    }
}

private struct PeerTubeCommentList: Decodable, Sendable {
    let total: Int
    let data: [PeerTubeComment]
}

private struct PeerTubeComment: Decodable, Sendable {
    let id: Int
    let threadId: Int
    let text: String
    let createdAt: String?
    let updatedAt: String?
    let account: PeerTubeAccount?
    let totalReplies: Int?
    let totalRepliesFromVideoAuthor: Int?

    private enum CodingKeys: String, CodingKey {
        case id, text, account
        case threadId, createdAt, updatedAt, totalReplies, totalRepliesFromVideoAuthor
    }

    nonisolated func toComment(instanceURL: URL) -> Comment {
        let publishDate = createdAt.flatMap { ISO8601DateFormatter().date(from: $0) }

        return Comment(
            id: String(id),
            author: Author(
                id: account?.name ?? "",
                name: account?.displayName ?? "",
                thumbnailURL: account?.avatar.map { instanceURL.appendingPathComponent($0.path) },
                instance: instanceURL
            ),
            content: text,
            publishedAt: publishDate,
            replyCount: totalReplies ?? 0
        )
    }
}
