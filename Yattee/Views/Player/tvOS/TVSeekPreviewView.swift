//
//  TVSeekPreviewView.swift
//  Yattee
//
//  Storyboard preview thumbnail for tvOS seek bar during scrubbing.
//

#if os(tvOS)
import SwiftUI

/// Glass capsule showing the current chapter title above the tvOS seek preview.
struct TVChapterCapsuleView: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 24, weight: .medium))
            .lineLimit(1)
            .truncationMode(.tail)
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .glassBackground(
                .regular,
                in: .capsule,
                fallback: .ultraThinMaterial,
                colorScheme: .dark
            )
            .shadow(radius: 4)
    }

    /// Returns this capsule horizontally positioned so its center follows `xTarget`
    /// and clamped to stay within `margin` of each edge of `availableWidth`. The
    /// capsule keeps its intrinsic text width (single-line, truncated if it cannot
    /// fit). Wrap the result in `.position(...)` to place it vertically; it occupies
    /// the full `availableWidth` horizontally.
    func positioned(xTarget: CGFloat, availableWidth: CGFloat, margin: CGFloat = 40) -> some View {
        self
            .alignmentGuide(.leading) { d in
                let targetLeading = xTarget - d.width / 2
                let clampedLeading = max(margin, min(availableWidth - d.width - margin, targetLeading))
                return -clampedLeading
            }
            .frame(width: availableWidth, alignment: .leading)
    }
}

/// Preview thumbnail displayed during scrubbing on tvOS.
/// Scaled up for TV viewing distance.
struct TVSeekPreviewView: View {
    let storyboard: Storyboard
    let seekTime: TimeInterval

    @State private var thumbnail: UIImage?
    @State private var loadTask: Task<Void, Never>?

    private let thumbnailWidth: CGFloat = 320

    var body: some View {
        Group {
            if let thumbnail {
                Image(uiImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                // Placeholder while loading
                Rectangle()
                    .fill(Color.gray.opacity(0.3))
            }
        }
        .frame(width: thumbnailWidth, height: 180)
        .clipped()
        .clipShape(.rect(cornerRadius: 4))
        .padding(4)
        .glassBackground(
            .regular,
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
            let service = StoryboardService.shared

            // First try to get cached thumbnail
            if let cached = await service.thumbnail(for: time, from: storyboard) {
                await MainActor.run {
                    self.thumbnail = cached
                }
                return
            }

            // Load the sheet and nearby sheets
            await service.preloadNearbySheets(around: time, from: storyboard)

            // Check for cancellation
            guard !Task.isCancelled else { return }

            // Try again after loading
            if let loaded = await service.thumbnail(for: time, from: storyboard) {
                await MainActor.run {
                    self.thumbnail = loaded
                }
            }
        }
    }
}

#endif
