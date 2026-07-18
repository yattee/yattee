//
//  PlayerInfoTab.swift
//  Yattee
//
//  Player info tab definitions.
//

import Foundation

enum PlayerInfoTab: String, CaseIterable {
    case description
    case comments

    var title: String {
        switch self {
        case .description: return String(localized: "player.description")
        case .comments: return String(localized: "player.comments")
        }
    }
}
