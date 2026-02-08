//  ChannelStripSize.swift
//  Yattee
//
//  Defines size options for the channel strip in Subscriptions view

import Foundation

enum ChannelStripSize: String, CaseIterable, Codable, Hashable, Sendable {
    case disabled
    case compact
    case normal
    case large
    
    // Avatar size in points
    var avatarSize: CGFloat {
        switch self {
        case .disabled: return 0
        case .compact: return 30
        case .normal: return 44
        case .large: return 65
        }
    }
    
    // Scaled spacing between avatars (proportional to avatar size)
    var chipSpacing: CGFloat {
        switch self {
        case .disabled: return 0
        case .compact: return 8
        case .normal: return 12
        case .large: return 16
        }
    }
    
    // Vertical padding for the channel strip container
    var verticalPadding: CGFloat {
        switch self {
        case .disabled: return 0
        case .compact: return 8
        case .normal: return 12
        case .large: return 16
        }
    }

    // Total height of the channel strip including avatar, padding, and container margin
    var totalHeight: CGFloat {
        guard self != .disabled else { return 0 }
        // avatarSize + vertical padding (top + bottom) + container bottom padding (8)
        return avatarSize + (verticalPadding * 2) + 8
    }

    var displayName: String {
        switch self {
        case .disabled: return String(localized: "common.disabled")
        case .compact: return String(localized: "channelStrip.size.compact")
        case .normal: return String(localized: "channelStrip.size.normal")
        case .large: return String(localized: "channelStrip.size.large")
        }
    }
}
