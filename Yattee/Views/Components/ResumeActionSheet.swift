//
//  ResumeActionSheet.swift
//  Yattee
//
//  Sheet displayed when playing a partially watched video to choose resume action.
//

import SwiftUI

/// A sheet that appears when playing a partially watched video, offering options to resume or start over.
struct ResumeActionSheet: View {
    let video: Video
    let resumeTime: TimeInterval
    let onContinue: () -> Void
    let onStartOver: () -> Void

    @Environment(\.dismiss) private var dismiss

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
                // Continue Watching (primary action)
                Button {
                    onContinue()
                    dismiss()
                } label: {
                    HStack {
                        Label(
                            String(localized: "resume.action.continueAt \(formattedResumeTime)"),
                            systemImage: "play.fill"
                        )
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

                // Start from Beginning
                Button {
                    onStartOver()
                    dismiss()
                } label: {
                    HStack {
                        Label(
                            String(localized: "resume.action.startFromBeginning"),
                            systemImage: "arrow.counterclockwise"
                        )
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
        .presentationDetents([.height(240)])
        .presentationDragIndicator(.hidden)
        .presentationCornerRadius(16)
    }

    // MARK: - Formatting

    private var formattedResumeTime: String {
        let hours = Int(resumeTime) / 3600
        let minutes = (Int(resumeTime) % 3600) / 60
        let seconds = Int(resumeTime) % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%d:%02d", minutes, seconds)
        }
    }
}

#Preview {
    Text("Tap me")
        .sheet(isPresented: .constant(true)) {
            ResumeActionSheet(
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
                ),
                resumeTime: 125,
                onContinue: {},
                onStartOver: {}
            )
        }
}
