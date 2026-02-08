//
//  VideoRowStyle.swift
//  Yattee
//
//  Row style configuration for VideoRowView.
//

import Foundation

/// Row style for VideoRowView.
enum VideoRowStyle: String {
    /// Large size with 160x90 thumbnail (220x124 on tvOS) and 3-line titles.
    case large
    /// Regular size with 120x68 thumbnail (180x101 on tvOS) and 2-line titles.
    case regular
    /// Compact size with 70x39 thumbnail (120x68 on tvOS), 1-line titles, hidden metadata, and duration shown inline.
    case compact

    var thumbnailWidth: CGFloat {
        switch self {
        case .large:
            #if os(tvOS)
            return 220
            #else
            return 160
            #endif
        case .regular:
            #if os(tvOS)
            return 180
            #else
            return 120
            #endif
        case .compact:
            #if os(tvOS)
            return 120
            #else
            return 70
            #endif
        }
    }

    var thumbnailHeight: CGFloat {
        switch self {
        case .large:
            #if os(tvOS)
            return 124
            #else
            return 90
            #endif
        case .regular:
            #if os(tvOS)
            return 101
            #else
            return 68
            #endif
        case .compact:
            #if os(tvOS)
            return 68
            #else
            return 39
            #endif
        }
    }
}
