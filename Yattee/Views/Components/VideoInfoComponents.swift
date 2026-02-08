//
//  VideoInfoComponents.swift
//  Yattee
//
//  Shared components for displaying video information in player views.
//

import SwiftUI

// MARK: - Video Stats Row

/// Displays video statistics: view count, date, likes, and dislikes.
/// Uses NotificationCenter to ensure updates propagate across separate window context.
struct VideoStatsRow: View {
    let playerState: PlayerState?
    @Binding var showFormattedDate: Bool
    let returnYouTubeDislikeEnabled: Bool

    // State to force re-render when notification received
    @State private var refreshTrigger: Int = 0

    private var video: Video? { playerState?.currentVideo }
    private var dislikeCount: Int? { playerState?.dislikeCount }

    /// Whether API stats are actively loading (show placeholders only in this case).
    private var isLoadingAPIStats: Bool {
        guard let video = playerState?.currentVideo else { return false }
        return video.supportsAPIStats && playerState?.videoDetailsState == .loading
    }

    var body: some View {
        if let video {
            statsContent(video, dislikeCount: dislikeCount)
                .id(refreshTrigger) // Force view recreation
                .onReceive(NotificationCenter.default.publisher(for: .videoDetailsDidLoad)) { _ in
                    refreshTrigger += 1
                }
        }
    }

    @ViewBuilder
    private func statsContent(_ video: Video, dislikeCount: Int?) -> some View {
        HStack(spacing: 4) {
            // Date
            if showFormattedDate, let publishedAt = video.publishedAt {
                Text(publishedAt.formatted(date: .long, time: .omitted))
                    .onTapGesture { showFormattedDate.toggle() }
            } else if let publishedText = video.formattedPublishedDate {
                Text(publishedText)
                    .onTapGesture { showFormattedDate.toggle() }
            } else if isLoadingAPIStats {
                Text("2 weeks ago")
                    .redacted(reason: .placeholder)
            }

            // View count
            if let viewCount = video.formattedViewCount {
                Text("•")
                Text("video.views \(viewCount)")
            } else if isLoadingAPIStats {
                Text("•")
                Text("video.views 1.2M")
                    .redacted(reason: .placeholder)
            }

            Spacer()

            // Like count
            if let likeCount = video.likeCount {
                CompactLabel(text: CountFormatter.compact(likeCount), systemImage: "hand.thumbsup")
            } else if isLoadingAPIStats {
                CompactLabel(text: "2.5K", systemImage: "hand.thumbsup")
                    .redacted(reason: .placeholder)
            }

            // Dislike count
            if returnYouTubeDislikeEnabled {
                if let dislikeCount {
                    CompactLabel(text: CountFormatter.compact(dislikeCount), systemImage: "hand.thumbsdown")
                } else if isLoadingAPIStats {
                    CompactLabel(text: "500", systemImage: "hand.thumbsdown")
                        .redacted(reason: .placeholder)
                }
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }
}

// MARK: - Video Channel Row

/// Displays channel info with avatar, name, subscriber count, and context menu.
struct VideoChannelRow: View {
    let author: Author
    let source: ContentSource
    let yatteeServerURL: URL?
    let onChannelTap: (() -> Void)?
    let video: Video
    let accentColor: Color
    var showSubscriberCount: Bool = true
    var isLoadingDetails: Bool = false

    var body: some View {
        HStack(spacing: 12) {
            if let onChannelTap {
                Button {
                    onChannelTap()
                } label: {
                    channelContent
                }
                .buttonStyle(.plain)
            } else {
                channelContent
            }

            Spacer()

            #if !os(tvOS)
            VideoContextMenuView(
                video: video,
                accentColor: accentColor
            )
            #endif
        }
        .padding(.top, 4)
    }

    private var channelContent: some View {
        HStack(spacing: 10) {
            ChannelAvatarView(
                author: author,
                size: 40,
                yatteeServerURL: yatteeServerURL,
                source: source
            )

            VStack(alignment: .leading, spacing: 2) {
                Text(author.name)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(1)

                if showSubscriberCount {
                    Group {
                        if let subscribers = author.formattedSubscriberCount {
                            Text(subscribers)
                        } else if isLoadingDetails && video.supportsAPIStats {
                            Text("1.2M subscribers")
                                .redacted(reason: .placeholder)
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                }
            }
        }
    }
}

