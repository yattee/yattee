//
//  TVSeekPreviewView.swift
//  Yattee
//
//  Storyboard preview thumbnail for tvOS seek bar during scrubbing.
//

#if os(tvOS)
import SwiftUI

/// Preview thumbnail displayed during scrubbing on tvOS.
/// Scaled up for TV viewing distance.
struct TVSeekPreviewView: View {
    let storyboard: Storyboard
    let seekTime: TimeInterval
    let chapters: [VideoChapter]

    @State private var thumbnail: UIImage?
    @State private var loadTask: Task<Void, Never>?

    /// The current chapter based on seek time.
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

    private let thumbnailWidth: CGFloat = 320

    var body: some View {
        VStack(spacing: 12) {
            // Chapter name (only shown if chapters exist, larger for TV)
            // Constrained to thumbnail width to prevent expanding the preview
            if let chapter = currentChapter {
                Text(chapter.title)
                    .font(.system(size: 28, weight: .medium))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .truncationMode(.tail)
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.8), radius: 3, x: 0, y: 1)
                    .frame(maxWidth: thumbnailWidth)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // Thumbnail with timestamp overlay (scaled up for TV)
            ZStack(alignment: .bottom) {
                Group {
                    if let thumbnail {
                        Image(uiImage: thumbnail)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                    } else {
                        // Placeholder while loading
                        Rectangle()
                            .fill(Color.gray.opacity(0.3))
                    }
                }

                // Timestamp overlaid at bottom center (larger for TV)
                Text(formattedTime)
                    .font(.system(size: 36, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.black.opacity(0.7))
                    .clipShape(.rect(cornerRadius: 6))
                    .padding(.bottom, 8)
            }
            .frame(width: thumbnailWidth, height: 180)
            .clipShape(.rect(cornerRadius: 8))
        }
        .padding(16)
        .background(.ultraThinMaterial)
        .clipShape(.rect(cornerRadius: 16))
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
