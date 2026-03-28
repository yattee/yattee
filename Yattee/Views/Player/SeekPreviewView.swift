//
//  SeekPreviewView.swift
//  Yattee
//
//  Preview thumbnail shown above the seek bar during scrubbing.
//

import SwiftUI

/// Glass capsule showing the current chapter title during seeking.
struct ChapterCapsuleView: View {
    let title: String
    let buttonBackground: ButtonBackgroundStyle

    var body: some View {
        Text(title)
            .font(.caption)
            .fontWeight(.medium)
            .lineLimit(1)
            .truncationMode(.tail)
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .glassBackground(
                buttonBackground.glassStyle ?? .regular,
                in: .capsule,
                fallback: .ultraThinMaterial,
                colorScheme: .dark
            )
            .shadow(radius: 4)
    }

    /// Returns this capsule positioned so its center follows `xTarget`,
    /// clamped to stay within `margin` of each edge of `availableWidth`.
    func positioned(xTarget: CGFloat, availableWidth: CGFloat, margin: CGFloat = 8) -> some View {
        self
            .alignmentGuide(.leading) { d in
                let targetLeading = xTarget - d.width / 2
                let clampedLeading = max(margin, min(availableWidth - d.width - margin, targetLeading))
                return -clampedLeading
            }
            .frame(width: availableWidth, alignment: .leading)
    }
}

/// Preview thumbnail displayed above the seek bar during scrubbing/hovering.

struct SeekPreviewView: View {
    let storyboard: Storyboard
    let seekTime: TimeInterval
    let storyboardService: StoryboardService
    let buttonBackground: ButtonBackgroundStyle
    let theme: ControlsTheme

    @State private var thumbnail: PlatformImage?
    @State private var loadTask: Task<Void, Never>?

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

    private let thumbnailWidth: CGFloat = 160

    var body: some View {
        // Thumbnail with timestamp overlay
        VStack(spacing: 4) {
            ZStack(alignment: .bottom) {
                Group {
                    if let thumbnail {
                        #if os(macOS)
                        Image(nsImage: thumbnail)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                        #else
                        Image(uiImage: thumbnail)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                        #endif
                    } else {
                        // Placeholder while loading
                        Rectangle()
                            .fill(Color.gray.opacity(0.3))
                    }
                }
                .frame(width: thumbnailWidth, height: 90)
                .clipped()

                // Timestamp overlaid at bottom center
                Text(formattedTime)
                    .font(.caption)
                    .fontWeight(.medium)
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.black.opacity(0.7))
                    .clipShape(.rect(cornerRadius: 4))
                    .padding(.bottom, 4)
            }
            .clipShape(.rect(cornerRadius: 4))
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 4)
        .glassBackground(
            buttonBackground.glassStyle ?? .regular,
            in: .rect(cornerRadius: 8),
            fallback: .ultraThinMaterial,
            colorScheme: .dark
        )
        .shadow(radius: 4)
        .onChange(of: seekTime) { _, newTime in
            loadThumbnail(for: newTime)
        }
        .onAppear {
            loadThumbnail(for: seekTime)
        }
        .onDisappear {
            loadTask?.cancel()
        }
    }

    private func loadThumbnail(for time: TimeInterval) {
        loadTask?.cancel()

        loadTask = Task {
            // First try to get cached thumbnail
            if let cached = await storyboardService.thumbnail(for: time, from: storyboard) {
                await MainActor.run {
                    self.thumbnail = cached
                }
                return
            }

            // Load the sheet and nearby sheets
            await storyboardService.preloadNearbySheets(around: time, from: storyboard)

            // Check for cancellation
            guard !Task.isCancelled else { return }

            // Try again after loading
            if let loaded = await storyboardService.thumbnail(for: time, from: storyboard) {
                await MainActor.run {
                    self.thumbnail = loaded
                }
            }
        }
    }
}
