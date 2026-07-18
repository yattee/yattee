//
//  PeerTubeDirectoryInstance.swift
//  Yattee
//
//  Model for PeerTube instances from the public directory.
//

import Foundation

/// Represents a PeerTube instance from the public directory at instances.joinpeertube.org.
struct PeerTubeDirectoryInstance: Identifiable, Decodable, Sendable {
    let id: Int
    let host: String
    let name: String
    let shortDescription: String?
    let version: String?
    let signupAllowed: Bool
    let languages: [String]
    let country: String?
    let totalUsers: Int
    let totalVideos: Int
    let totalLocalVideos: Int?
    let health: Int?
    let createdAt: String?

    /// Constructs the full URL for this instance.
    var url: URL? {
        URL(string: "https://\(host)")
    }
}

/// Response wrapper for the PeerTube instances directory API.
struct PeerTubeDirectoryResponse: Decodable, Sendable {
    let total: Int
    let data: [PeerTubeDirectoryInstance]
}

/// Filters for browsing the PeerTube instance directory.
struct PeerTubeDirectoryFilters: Equatable, Sendable {
    var searchText: String = ""
    var language: String? = nil
    var country: String? = nil

    var isDefault: Bool {
        searchText.isEmpty && language == nil && country == nil
    }
}
