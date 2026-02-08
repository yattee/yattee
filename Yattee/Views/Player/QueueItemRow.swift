//
//  QueueItemRow.swift
//  Yattee
//
//  A row displaying a queued video with drag handle and remove action.
//

import SwiftUI

struct QueueItemRow: View {
    @Environment(\.appEnvironment) private var appEnvironment

    let queuedVideo: QueuedVideo
    /// Position in queue (nil hides the number, used for history items)
    let index: Int?
    let isCurrentlyPlaying: Bool
    let onRemove: () -> Void
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // Index number or playing indicator
                Group {
                    if isCurrentlyPlaying {
                        Image(systemName: "waveform")
                            .font(.caption)
                            .foregroundStyle(.tint)
                            .symbolEffect(.variableColor.iterative, options: .repeating)
                    } else if let index {
                        Text("\(index)")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundStyle(.secondary)
                    } else {
                        // No index - show empty space (for history items)
                        Color.clear
                    }
                }
                .frame(width: 24)

                // Thumbnail
                DeArrowVideoThumbnail(
                    video: queuedVideo.video,
                    cornerRadius: 6,
                    duration: queuedVideo.video.formattedDuration
                )
                .frame(width: 80, height: 45)
                .opacity(isCurrentlyPlaying ? 0.6 : 1.0)

                // Video info
                VStack(alignment: .leading, spacing: 2) {
                    Text(queuedVideo.video.displayTitle(using: appEnvironment?.deArrowBrandingProvider))
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .lineLimit(2)
                        .foregroundStyle(isCurrentlyPlaying ? .secondary : .primary)

                    Text(queuedVideo.video.author.name)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        #if !os(tvOS)
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                onRemove()
            } label: {
                Label(String(localized: "queue.item.remove"), systemImage: "trash")
            }
        }
        #endif
        .opacity(isCurrentlyPlaying ? 0.8 : 1.0)
    }
}
