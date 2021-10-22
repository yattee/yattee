import CoreMedia
import Foundation
import SDWebImageSwiftUI
import SwiftUI

struct VideoBanner: View {
    let video: Video
    var playbackTime: CMTime?
    var videoDuration: TimeInterval?

    init(video: Video, playbackTime: CMTime? = nil, videoDuration: TimeInterval? = nil) {
        self.video = video
        self.playbackTime = playbackTime
        self.videoDuration = videoDuration
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: thumbnailStackSpacing) {
                smallThumbnail

                if !playbackTime.isNil {
                    ProgressView(value: progressViewValue, total: progressViewTotal)
                        .progressViewStyle(.linear)
                        .frame(maxWidth: thumbnailWidth)
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(video.title)
                    .truncationMode(.middle)
                    .lineLimit(2)
                    .font(.headline)
                    .frame(alignment: .leading)

                HStack {
                    Text(video.author)
                        .lineLimit(1)

                    Spacer()

                    if let time = (videoDuration ?? video.length).formattedAsPlaybackTime() {
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

    private var thumbnailStackSpacing: Double {
        #if os(tvOS)
            8
        #else
            3
        #endif
    }

    private var smallThumbnail: some View {
        WebImage(url: video.thumbnailURL(quality: .medium))
            .resizable()
            .placeholder {
                ProgressView()
            }
            .indicator(.activity)
        #if os(tvOS)
            .frame(width: thumbnailWidth, height: 100)
            .mask(RoundedRectangle(cornerRadius: 12))
        #else
            .frame(width: thumbnailWidth, height: 50)
            .mask(RoundedRectangle(cornerRadius: 6))
        #endif
    }

    private var thumbnailWidth: Double {
        #if os(tvOS)
            177
        #else
            88
        #endif
    }

    private var progressViewValue: Double {
        [playbackTime?.seconds, videoDuration].compactMap { $0 }.min() ?? 0
    }

    private var progressViewTotal: Double {
        videoDuration ?? video.length
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
