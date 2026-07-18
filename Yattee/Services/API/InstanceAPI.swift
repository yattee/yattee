//
//  InstanceAPI.swift
//  Yattee
//
//  Protocol defining the API interface that each backend must implement.
//

import Foundation

/// Protocol that each backend API (Invidious, Piped, PeerTube) must implement.
protocol InstanceAPI: Sendable {
    func trending(instance: Instance) async throws -> [Video]
    func popular(instance: Instance) async throws -> [Video]
    func search(query: String, instance: Instance, page: Int, filters: SearchFilters) async throws -> SearchResult
    func searchSuggestions(query: String, instance: Instance) async throws -> [String]
    func video(id: String, instance: Instance) async throws -> Video
    func channel(id: String, instance: Instance) async throws -> Channel
    func channelVideos(id: String, instance: Instance, continuation: String?) async throws -> ChannelVideosPage
    func channelPlaylists(id: String, instance: Instance, continuation: String?) async throws -> ChannelPlaylistsPage
    func channelShorts(id: String, instance: Instance, continuation: String?) async throws -> ChannelVideosPage
    func channelStreams(id: String, instance: Instance, continuation: String?) async throws -> ChannelVideosPage
    func playlist(id: String, instance: Instance) async throws -> Playlist
    func comments(videoID: String, instance: Instance, continuation: String?) async throws -> CommentsPage
    func streams(videoID: String, instance: Instance) async throws -> [Stream]
    func captions(videoID: String, instance: Instance) async throws -> [Caption]
    func channelSearch(id: String, query: String, instance: Instance, page: Int) async throws -> ChannelSearchPage
}

// MARK: - Default Implementations

extension InstanceAPI {
    /// Default implementation for backends that don't distinguish popular from trending.
    func popular(instance: Instance) async throws -> [Video] {
        try await trending(instance: instance)
    }

    /// Default implementation for backends that don't support search suggestions.
    func searchSuggestions(query: String, instance: Instance) async throws -> [String] {
        []
    }

    /// Default implementation for backends that don't support captions.
    func captions(videoID: String, instance: Instance) async throws -> [Caption] {
        []
    }

    /// Default implementation for backends that don't support channel playlists tab.
    func channelPlaylists(id: String, instance: Instance, continuation: String?) async throws -> ChannelPlaylistsPage {
        ChannelPlaylistsPage(playlists: [], continuation: nil)
    }

    /// Default implementation for backends that don't support channel shorts tab.
    func channelShorts(id: String, instance: Instance, continuation: String?) async throws -> ChannelVideosPage {
        ChannelVideosPage(videos: [], continuation: nil)
    }

    /// Default implementation for backends that don't support channel streams tab.
    func channelStreams(id: String, instance: Instance, continuation: String?) async throws -> ChannelVideosPage {
        ChannelVideosPage(videos: [], continuation: nil)
    }

    /// Default implementation for backends that don't support channel search.
    func channelSearch(id: String, query: String, instance: Instance, page: Int) async throws -> ChannelSearchPage {
        throw APIError.notSupported
    }
}
