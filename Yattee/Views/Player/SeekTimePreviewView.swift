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

    private var formattedTime: String {
        let totalSeconds = Int(seekTime)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%d:%02d", minutes, seconds)
        }
    }

    var body: some View {
        Text(formattedTime)
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
