//
//  GitHubContributor.swift
//  Yattee
//
//  Data model for GitHub contributor information.
//

import Foundation

/// A GitHub repository contributor.
struct GitHubContributor: Identifiable, Decodable, Sendable {
    let id: Int
    let login: String
    let avatarUrl: String
    let htmlUrl: String
    let contributions: Int

    var avatarURL: URL? { URL(string: avatarUrl) }
    var profileURL: URL? { URL(string: htmlUrl) }
}
