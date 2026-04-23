//
//  MediaFileTapModifier.swift
//  Yattee
//
//  Helpers that route taps on a playable MediaFileRow according to the
//  user's per-platform tap-action settings. Mirrors the split used by
//  VideoRowView (iOS/macOS per-region) and TappableVideoModifier (tvOS).
//

import SwiftUI

#if os(tvOS)
/// tvOS-only: wraps the row in a Button that honors `tvOSVideoTapAction`.
struct MediaFileTVOSTapButton<Label: View>: View {
    @Environment(\.appEnvironment) private var appEnvironment

    let onPlay: () -> Void
    let onOpenInfo: () -> Void
    @ViewBuilder let label: () -> Label

    var body: some View {
        Button {
            let action = appEnvironment?.settingsManager.tvOSVideoTapAction ?? .openInfo
            switch action {
            case .playVideo:
                onPlay()
            case .openInfo:
                onOpenInfo()
            case .none:
                break
            }
        } label: {
            label()
        }
    }
}

/// tvOS-only: wraps an unplayable row in a Button so the focus engine can land on it.
struct MediaFileTVOSUnsupportedButton<Label: View>: View {
    let onTap: () -> Void
    @ViewBuilder let label: () -> Label

    var body: some View {
        Button(action: onTap) { label() }
    }
}
#else
/// iOS/macOS: per-region gesture used by MediaFileRow's icon and text areas.
/// Only attaches a gesture when the action differs from `.playVideo`, letting
/// the row's outer `onTapGesture { onPlay() }` handle the default case.
struct MediaFileRegionTapGesture: ViewModifier {
    let action: VideoTapAction
    let onPlay: () -> Void
    let onOpenInfo: () -> Void

    func body(content: Content) -> some View {
        if action == .playVideo {
            content
        } else {
            content.highPriorityGesture(
                TapGesture().onEnded {
                    switch action {
                    case .playVideo:
                        onPlay()
                    case .openInfo:
                        onOpenInfo()
                    case .none:
                        break
                    }
                }
            )
        }
    }
}

extension View {
    func mediaFileRegionTap(
        action: VideoTapAction,
        onPlay: @escaping () -> Void,
        onOpenInfo: @escaping () -> Void
    ) -> some View {
        modifier(MediaFileRegionTapGesture(action: action, onPlay: onPlay, onOpenInfo: onOpenInfo))
    }
}
#endif
