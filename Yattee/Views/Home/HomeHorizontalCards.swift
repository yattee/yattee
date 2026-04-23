//
//  HomeHorizontalCards.swift
//  Yattee
//
//  Horizontal shelf of video cards for Home sections in grid layout mode.
//

import SwiftUI

/// A horizontally scrolling row of `VideoCardView` cards used by Home sections
/// when `HomeSectionLayout.grid` is selected.
struct HomeHorizontalCards: View {
    let videos: [Video]
    let queueSource: QueueSource
    let sourceLabel: String
    var loadMoreVideos: LoadMoreVideosCallback? = nil

    #if os(tvOS)
    private let cardWidth: CGFloat = 320
    private let cardHeight: CGFloat = 340
    private let spacing: CGFloat = 60
    private let verticalPadding: CGFloat = 28
    #else
    private let cardWidth: CGFloat = 180
    private let cardHeight: CGFloat = 210
    private let spacing: CGFloat = 28
    private let verticalPadding: CGFloat = 8
    #endif

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(alignment: .top, spacing: spacing) {
                ForEach(Array(videos.enumerated()), id: \.element.id) { index, video in
                    VideoCardView(video: video, isCompact: true)
                        .frame(width: cardWidth, height: cardHeight, alignment: .top)
                        .tappableVideo(
                            video,
                            queueSource: queueSource,
                            sourceLabel: sourceLabel,
                            videoList: videos,
                            videoIndex: index,
                            loadMoreVideos: loadMoreVideos
                        )
                }
            }
            .padding(.horizontal)
            .padding(.vertical, verticalPadding)
            #if os(tvOS)
            .focusSection()
            #endif
        }
    }
}
