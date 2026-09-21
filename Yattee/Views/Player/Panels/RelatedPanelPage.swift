//
//  RelatedPanelPage.swift
//  Yattee
//
//  Details panel page listing videos related to the current one.
//

import SwiftUI

#if os(iOS) || os(macOS)

struct RelatedPanelPage: View {
    let context: PanelPageContext
    var scrollConfig: PanelScrollConfig = PanelScrollConfig()

    private var relatedVideos: [Video] { context.video.relatedVideos ?? [] }

    var body: some View {
        PanelPageScrollView(config: scrollConfig) {
            if relatedVideos.isEmpty {
                emptyState
            } else {
                LazyVStack(spacing: 12) {
                    ForEach(Array(relatedVideos.enumerated()), id: \.element.id) { index, relatedVideo in
                        VideoRowView(video: relatedVideo, style: .regular)
                            .tappableVideo(
                                relatedVideo,
                                queueSource: .manual,
                                sourceLabel: String(localized: "videoInfo.section.relatedVideos"),
                                videoList: relatedVideos,
                                videoIndex: index,
                                loadMoreVideos: nil
                            )

                        if index < relatedVideos.count - 1 {
                            Divider()
                                .padding(.leading, VideoRowStyle.regular.thumbnailWidth + 12)
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.top, 8)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "rectangle.stack.badge.play")
                .font(.title2)
                .foregroundStyle(.secondary)
            Text(String(localized: "videoInfo.section.relatedVideos"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
    }
}

#endif
