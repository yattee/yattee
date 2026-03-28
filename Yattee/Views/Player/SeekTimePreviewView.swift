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
    let chapters: [VideoChapter]

    private var currentChapter: VideoChapter? {
        chapters.last { $0.startTime <= seekTime }
    }

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
        VStack(spacing: 4) {
            if let chapter = currentChapter {
                Text(chapter.title)
                    .font(.caption)
                    .fontWeight(.medium)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.8), radius: 2, x: 0, y: 1)
            }

            Text(formattedTime)
                .font(.system(size: 16, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(.white)
        }
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
