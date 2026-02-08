//
//  RecentPlaylist.swift
//  Yattee
//
//  SwiftData model for recent playlist visits (remote playlists only).
//

import Foundation
import SwiftData

@Model
final class RecentPlaylist {
    var id: UUID
    var playlistID: String
    var sourceRawValue: String
    var instanceURLString: String?
    var title: String
    var authorName: String
    var videoCount: Int
    var thumbnailURLString: String?
    var visitedAt: Date
    
    init(
        id: UUID = UUID(),
        playlistID: String,
        sourceRawValue: String,
        instanceURLString: String? = nil,
        title: String,
        authorName: String = "",
        videoCount: Int = 0,
        thumbnailURLString: String? = nil,
        visitedAt: Date = Date()
    ) {
        self.id = id
        self.playlistID = playlistID
        self.sourceRawValue = sourceRawValue
        self.instanceURLString = instanceURLString
        self.title = title
        self.authorName = authorName
        self.videoCount = videoCount
        self.thumbnailURLString = thumbnailURLString
        self.visitedAt = visitedAt
    }
    
    /// Creates a RecentPlaylist from a Playlist model
    /// Returns nil for local playlists (we only track remote ones)
    static func from(playlist: Playlist) -> RecentPlaylist? {
        guard !playlist.isLocal, let source = playlist.id.source else {
            return nil
        }
        
        let (sourceRaw, instanceURL) = extractSourceInfo(from: source)
        return RecentPlaylist(
            playlistID: playlist.id.playlistID,
            sourceRawValue: sourceRaw,
            instanceURLString: instanceURL,
            title: playlist.title,
            authorName: playlist.authorName,
            videoCount: playlist.videoCount,
            thumbnailURLString: playlist.thumbnailURL?.absoluteString
        )
    }
    
    private static func extractSourceInfo(from source: ContentSource) -> (String, String?) {
        switch source {
        case .global:
            return ("global", nil)
        case .federated(_, let instance):
            return ("federated", instance.absoluteString)
        case .extracted:
            return ("extracted", nil)
        }
    }
}
