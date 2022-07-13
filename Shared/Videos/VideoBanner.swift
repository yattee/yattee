import CoreMedia
import Foundation
import SDWebImageSwiftUI
import SwiftUI

struct VideoBanner: View {
    let video: Video?
    var playbackTime: CMTime?
    var videoDuration: TimeInterval?

    init(video: Video? = nil, playbackTime: CMTime? = nil, videoDuration: TimeInterval? = nil) {
        self.video = video
        self.playbackTime = playbackTime
        self.videoDuration = videoDuration
    }

    var body: some View {
        HStack(alignment: stackAlignment, spacing: 12) {
            VStack(spacing: thumbnailStackSpacing) {
                smallThumbnail

                #if !os(tvOS)
                    progressView
                #endif
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(video?.title ?? "Loading...")
                    .truncationMode(.middle)
                    .lineLimit(2)
                    .font(.headline)
                    .frame(alignment: .leading)

                HStack {
                    Text(video?.author ?? "")
                        .lineLimit(1)

                    Spacer()

                    #if os(tvOS)
                        progressView
                    #endif

                    if let time = (videoDuration ?? video?.length ?? 0).formattedAsPlaybackTime() {
                        Text(time)
                            .fontWeight(.light)
                    }
                }
                .foregroundColor(.secondary)
            }
            .padding(.vertical, playbackTime.isNil ? 0 : 5)
        }
        .contentShape(Rectangle())
        .buttonStyle(.plain)
        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: 100, alignment: .center)
    }

    private var stackAlignment: VerticalAlignment {
        #if os(macOS)
            playbackTime.isNil ? .center : .top
        #else
                .center
        #endif
    }

    private var thumbnailStackSpacing: Double {
        #if os(tvOS)
            8
        #else
            2
        #endif
    }

    private var smallThumbnail: some View {
        WebImage(url: video?.thumbnailURL(quality: .medium))
            .resizable()
            .placeholder {
                ProgressView()
            }
            .indicator(.activity)
        #if os(tvOS)
            .frame(width: thumbnailWidth, height: 140)
            .mask(RoundedRectangle(cornerRadius: 12))
        #else
            .frame(width: thumbnailWidth, height: 60)
            .mask(RoundedRectangle(cornerRadius: 6))
        #endif
    }

    private var thumbnailWidth: Double {
        #if os(tvOS)
            250
        #else
            100
        #endif
    }

    private var progressView: some View {
        Group {
            if !playbackTime.isNil, !(video?.live ?? false) {
                ProgressView(value: progressViewValue, total: progressViewTotal)
                    .progressViewStyle(.linear)
                    .frame(maxWidth: thumbnailWidth)
            }
        }
    }

    private var progressViewValue: Double {
        [playbackTime?.seconds, videoDuration].compactMap { $0 }.min() ?? 0
    }

    private var progressViewTotal: Double {
        videoDuration ?? video?.length ?? 1
    }
}

struct VideoBanner_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 20) {
            VideoBanner(video: Video.fixture, playbackTime: CMTime(seconds: 400, preferredTimescale: 10000))
            VideoBanner(video: Video.fixtureUpcomingWithoutPublishedOrViews)
        }
        .frame(maxWidth: 900)
    }
}
