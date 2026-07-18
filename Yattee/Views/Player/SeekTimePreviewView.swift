//
//  SeekTimePreviewView.swift
//  Yattee
//
//  Seek time preview shown when no storyboard thumbnails are available.
//

import SwiftUI

/// Lightweight seek time pill displayed above the seek bar when no storyboard is available.
struct SeekTimePreviewView: View {
    let seekTime: TimeInterval
    let buttonBackground: ButtonBackgroundStyle
    let theme: ControlsTheme

    var body: some View {
        Text(seekTime.formattedAsTimestamp)
            .font(.system(size: 16, weight: .medium))
            .monospacedDigit()
            .foregroundStyle(.white)
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .glassBackground(
                buttonBackground.glassStyle ?? .regular,
                in: .rect(cornerRadius: 8),
                fallback: .ultraThinMaterial,
                colorScheme: .dark
            )
            .shadow(radius: 4)
    }
}
