//
//  QualitySelectorTypes.swift
//  Yattee
//
//  Types used by QualitySelectorView and its components.
//

import Foundation

/// Tab selection for the quality selector view.
enum QualitySelectorTab: String, CaseIterable, Sendable {
    case video
    case audio
    case subtitles

    /// Localized display label for the tab.
    var label: String {
        switch self {
        case .video:
            String(localized: "player.quality.video")
        case .audio:
            String(localized: "stream.audio")
        case .subtitles:
            String(localized: "stream.subtitles")
        }
    }
}

/// Navigation destination for quality selector detail pages.
enum QualitySelectorDestination: Hashable {
    case video
    case audio
    case subtitles
}

/// Parsed audio track information for display.
struct AudioTrackInfo: Sendable {
    /// The formatted language name (e.g., "English", "Japanese").
    let language: String

    /// Track type badge text ("AD" for auto-dubbed, "ORIGINAL" for original audio, nil otherwise).
    let trackType: String?
}
