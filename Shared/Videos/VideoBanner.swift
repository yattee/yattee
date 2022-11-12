import CoreMedia
import Foundation
import SDWebImageSwiftUI
import SwiftUI

struct VideoBanner: View {
    #if os(tvOS)
        static let titleAppend = ""
    #else
        static let titleAppend = "\n"
    #endif

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
            ZStack(alignment: .bottom) {
                smallThumbnail

                #if !os(tvOS)
                    progressView
                #endif
            }
            VStack(alignment: .leading, spacing: 4) {
                Group {
                    if let video {
                        HStack(alignment: .top) {
                            Text(video.displayTitle + Self.titleAppend)
                            if video.isLocal, let fileExtension = video.localStreamFileExtension {
                                Spacer()
                                Text(fileExtension)
                                    .foregroundColor(.secondary)
                            }
                        }
                    } else {
                        Text("Loading contents of the video, please wait")
                            .redacted(reason: .placeholder)
                    }
                }
                .truncationMode(.middle)
                .lineLimit(2)
                .font(.headline)
                .frame(alignment: .leading)

                HStack {
                    Group {
                        if let video {
                            if !video.isLocal || video.localStreamIsRemoteURL {
                                Text(video.displayAuthor)
                            } else {
                                #if os(iOS)
                                    if DocumentsModel.shared.isDocument(video) {
                                        HStack(spacing: 6) {
                                            if let date = DocumentsModel.shared.formattedCreationDate(video) {
                                                Text(date)
                                            }
                                            if let size = DocumentsModel.shared.formattedSize(video) {
                                                Text("•")
                                                Text(size)
                                            }
                                        }
                                    }
                                #endif
                            }
                        } else {
                            Text("Video Author")
                                .redacted(reason: .placeholder)
                        }
                    }
                    .lineLimit(1)

                    Spacer()

                    #if os(tvOS)
                        progressView
                    #endif

                    if !(video?.localStreamIsDirectory ?? false) {
                        Text(videoDurationLabel)
                            .fontWeight(.light)
                    }
                }
                .foregroundColor(.secondary)
            }
            .padding(.vertical, playbackTime.isNil ? 0 : 5)
        }
        .contentShape(Rectangle())
        #if os(tvOS)
            .buttonStyle(.card)

        #else
            .buttonStyle(.plain)
        #endif
            .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: 100, alignment: .center)
        #if os(tvOS)
            .padding(.vertical, 20)
            .padding(.trailing, 10)
        #endif
    }

    private var stackAlignment: VerticalAlignment {
        #if os(macOS)
            playbackTime.isNil ? .center : .top
        #else
                .center
        #endif
    }

    @ViewBuilder private var smallThumbnail: some View {
        ZStack {
            Color("PlaceholderColor")
            if let video {
                if let thumbnail = video.thumbnailURL(quality: .medium) {
                    WebImage(url: thumbnail, options: [.lowPriority])
                        .resizable()
                } else if video.isLocal {
                    Image(systemName: video.localStreamImageSystemName)
                }
            } else {
                Image(systemName: "ellipsis")
            }
        }
        #if os(tvOS)
        .frame(width: thumbnailWidth, height: thumbnailHeight)
        .mask(RoundedRectangle(cornerRadius: 12))
        #else
        .frame(width: thumbnailWidth, height: thumbnailHeight)
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

    private var thumbnailHeight: Double {
        #if os(tvOS)
            140
        #else
            60
        #endif
    }

    private var videoDurationLabel: String {
        guard videoDuration != 0 else { return PlayerTimeModel.timePlaceholder }
        return (videoDuration ?? video?.length ?? 0).formattedAsPlaybackTime() ?? PlayerTimeModel.timePlaceholder
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
        guard videoDuration != 0 else { return 1 }
        return [playbackTime?.seconds, videoDuration].compactMap { $0 }.min() ?? 0
    }

    private var progressViewTotal: Double {
        guard videoDuration != 0 else { return 1 }
        return videoDuration ?? video?.length ?? 1
    }
}

struct VideoBanner_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 20) {
            VideoBanner(video: Video.fixture, playbackTime: CMTime(seconds: 400, preferredTimescale: 10000))
            VideoBanner(video: Video.fixtureUpcomingWithoutPublishedOrViews)
            VideoBanner(video: .local(URL(string: "https://apple.com/a/directory/of/video+that+has+very+long+title+that+will+likely.mp4")!))
            VideoBanner(video: .local(URL(string: "file://a/b/c/d/e/f.mkv")!))
            VideoBanner()
        }
        .frame(maxWidth: 900)
    }
}
