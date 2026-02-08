//
//  QueueActionSheet.swift
//  Yattee
//
//  Sheet displayed when tapping a video to choose playback or queue action.
//

import SwiftUI

/// A sheet that appears when tapping a video, offering options to play or add to queue.
struct QueueActionSheet: View {
    let video: Video
    var queueSource: QueueSource?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.appEnvironment) private var appEnvironment

    var body: some View {
        VStack(spacing: 0) {
            // Drag indicator
            RoundedRectangle(cornerRadius: 2.5)
                .fill(.secondary.opacity(0.5))
                .frame(width: 36, height: 5)
                .padding(.top, 8)
                .padding(.bottom, 16)

            // Video preview
            HStack(spacing: 12) {
                DeArrowVideoThumbnail(
                    video: video,
                    duration: video.formattedDuration
                )
                .frame(width: 120, height: 68)
                .clipShape(RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 4) {
                    Text(video.title)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .lineLimit(2)
                        .foregroundStyle(.primary)

                    Text(video.author.name)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)

            Divider()

            // Actions
            VStack(spacing: 0) {
                // Play Now (primary action)
                Button {
                    appEnvironment?.playerService.openVideo(video)
                    dismiss()
                } label: {
                    HStack {
                        Label(String(localized: "queue.action.playNow"), systemImage: "play.fill")
                            .font(.body)
                        Spacer()
                    }
                    .contentShape(Rectangle())
                    .padding(.horizontal, 20)
                    .padding(.vertical, 14)
                }
                .buttonStyle(.plain)

                Divider()
                    .padding(.leading, 56)

                // Play Next
                Button {
                    appEnvironment?.queueManager.playNext(video, queueSource: queueSource)
                    dismiss()
                } label: {
                    HStack {
                        Label(String(localized: "queue.action.playNext"), systemImage: "text.line.first.and.arrowtriangle.forward")
                            .font(.body)
                        Spacer()
                    }
                    .contentShape(Rectangle())
                    .padding(.horizontal, 20)
                    .padding(.vertical, 14)
                }
                .buttonStyle(.plain)

                Divider()
                    .padding(.leading, 56)

                // Add to Queue
                Button {
                    appEnvironment?.queueManager.addToQueue(video, queueSource: queueSource)
                    dismiss()
                } label: {
                    HStack {
                        Label(String(localized: "queue.action.addToQueue"), systemImage: "text.append")
                            .font(.body)
                        Spacer()
                    }
                    .contentShape(Rectangle())
                    .padding(.horizontal, 20)
                    .padding(.vertical, 14)
                }
                .buttonStyle(.plain)
            }

            Spacer()
        }
        .presentationDetents([.height(280)])
        .presentationDragIndicator(.hidden)
        .presentationCornerRadius(16)
    }
}

#Preview {
    Text("Tap me")
        .sheet(isPresented: .constant(true)) {
            QueueActionSheet(
                video: Video(
                    id: .global("dQw4w9WgXcQ"),
                    title: "Sample Video Title That Might Be Long",
                    description: nil,
                    author: Author(id: "UCtest", name: "Test Channel"),
                    duration: 212,
                    publishedAt: nil,
                    publishedText: "2 weeks ago",
                    viewCount: 1000000,
                    likeCount: 50000,
                    thumbnails: [],
                    isLive: false,
                    isUpcoming: false,
                    scheduledStartTime: nil
                )
            )
        }
}
