//
//  TVVideoSyncMode.swift
//  Yattee
//
//  MPV `video-sync` mode override exposed on tvOS for A/V sync debugging.
//

import SwiftUI

enum TVVideoSyncMode: String, CaseIterable, Codable {
    /// Lock video to display refresh, drop/repeat frames to match. Audio plays at PTS.
    /// Current shipping default.
    case displayVdrop = "display-vdrop"
    /// Lock video to display refresh; resample audio to match. Eliminates A/V drift
    /// when the display mode doesn't match content fps, at the cost of tiny audio
    /// pitch correction.
    case displayResample = "display-resample"
    /// libmpv default: video adjusts to audio. Most forgiving when display-mode
    /// matching is uncertain.
    case audio

    var displayName: LocalizedStringKey {
        switch self {
        case .displayVdrop: "settings.playback.tvVideoSyncMode.displayVdrop"
        case .displayResample: "settings.playback.tvVideoSyncMode.displayResample"
        case .audio: "settings.playback.tvVideoSyncMode.audio"
        }
    }
}
