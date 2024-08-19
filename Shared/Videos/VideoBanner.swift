import CoreMedia
import Defaults
import Foundation
import SDWebImageSwiftUI
import SwiftUI

struct VideoBanner: View {
    var id: String?
    let video: Video?
    var playbackTime: CMTime?
    var videoDuration: TimeInterval?
    var watch: Watch?

    @Default(.saveHistory) private var saveHistory
    @Default(.watchedVideoStyle) private var watchedVideoStyle
    @Default(.watchedVideoBadgeColor) private var watchedVideoBadgeColor
    @Default(.timeOnThumbnail) private var timeOnThumbnail
    @Default(.roundedThumbnails) private var roundedThumbnails
    @Default(.showChannelAvatarInVideosListing) private var showChannelAvatarInVideosListing

    @Environment(\.inChannelView) private var inChannelView
    @Environment(\.inNavigationView) private var inNavigationView
    @Environment(\.navigationStyle) private var navigationStyle

    init(
        id: String? = nil,
        video: Video? = nil,
        playbackTime: CMTime? = nil,
        videoDuration: TimeInterval? = nil,
        watch: Watch? = nil
    ) {
        self.id = id
        self.video = video
        self.playbackTime = playbackTime
        self.videoDuration = videoDuration
        self.watch = watch
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .trailing, spacing: 2) {
                ZStack(alignment: .bottom) {
                    smallThumbnail
                        .layoutPriority(1)

                    ProgressView(value: watch?.progress ?? 44, total: 100)
                        .frame(maxHeight: 4)
                        .progressViewStyle(LinearProgressViewStyle(tint: Color("AppRedColor")))
                        .opacity(watch?.isShowingProgress ?? false ? 1 : 0)
                }

                if !timeOnThumbnail, let timeLabel {
                    Text(timeLabel)
                        .font(.caption.monospacedDigit())
                        .foregroundColor(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Group {
                    if let video {
                        HStack(alignment: .top) {
                            Text(video.displayTitle)
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
                .lineLimit(5)
                .font(.headline)

                Spacer()

                HStack {
                    HStack {
                        VStack(alignment: .leading) {
                            Group {
                                if let video {
                                    if !inChannelView, !video.isLocal || video.localStreamIsRemoteURL {
                                        ChannelLinkView(channel: video.channel) {
                                            HStack(spacing: Constants.channelDetailsStackSpacing) {
                                                if video != .fixture, showChannelAvatarInVideosListing {
                                                    ChannelAvatarView(channel: video.channel)
                                                        .frame(width: Constants.channelThumbnailSize, height: Constants.channelThumbnailSize)
                                                }

                                                channelLabel
                                                    .font(.subheadline)
                                            }
                                        }
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

                                                    Spacer()
                                                }
                                                .frame(maxWidth: .infinity)
                                            }
                                        #endif
                                    }
                                } else {
                                    Text("Video Author")
                                        .redacted(reason: .placeholder)
                                }
                            }

                            extraAttributes
                        }
                    }
                    .foregroundColor(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(maxHeight: .infinity)
            #if os(tvOS)
                .padding(.vertical)
            #endif
        }
        .fixedSize(horizontal: false, vertical: true)
        #if os(tvOS)
            .buttonStyle(.card)
            .padding(.trailing, 10)
        #elseif os(macOS)
            .buttonStyle(.plain)
        #endif
            .opacity(contentOpacity)
            .contentShape(Rectangle())
    }

    private var thumbnailRoundingCornerRadius: Double {
        #if os(tvOS)
            return Double(12)
        #else
            return Double(roundedThumbnails ? 6 : 0)
        #endif
    }

    private var extraAttributes: some View {
        HStack(spacing: 16) {
            if let video {
                if let date = video.publishedDate {
                    HStack(spacing: 2) {
                        Text(date)
                            .allowsTightening(true)
                    }
                }

                if video.views > 0 {
                    HStack(spacing: 2) {
                        Image(systemName: "eye")
                        Text(video.viewsCount!)
                    }
                }
            }
        }
        .font(.caption)
        .lineLimit(1)
        .foregroundColor(.secondary)
    }

    @ViewBuilder private var smallThumbnail: some View {
        ZStack(alignment: .bottomTrailing) {
            ZStack(alignment: .topLeading) {
                ZStack {
                    Color("PlaceholderColor")

                    if let video {
                        if let thumbnail = video.thumbnailURL(quality: .medium) {
                            ThumbnailView(url: thumbnail)
                        } else if video.isLocal {
                            Image(systemName: video.localStreamImageSystemName)
                        }
                    } else {
                        Image(systemName: "ellipsis")
                    }
                }

                if saveHistory,
                   watchedVideoStyle.isShowingBadge,
                   let video
                {
                    WatchView(watch: watch, videoID: video.videoID, duration: video.length)
                        .offset(x: 2, y: 2)
                }
            }

            if timeOnThumbnail {
                timeView
                    .offset(y: watch?.isShowingProgress ?? false ? -4 : 0)
            }
        }
        .frame(width: thumbnailWidth, height: thumbnailHeight)
        .mask(RoundedRectangle(cornerRadius: thumbnailRoundingCornerRadius))
    }

    private var contentOpacity: Double {
        guard saveHistory,
              !watch.isNil,
              watchedVideoStyle.isDecreasingOpacity
        else {
            return 1
        }

        return watch!.finished ? 0.5 : 1
    }

    private var thumbnailHeight: Double {
        #if os(tvOS)
            200
        #else
            75
        #endif
    }

    private var thumbnailWidth: Double {
        thumbnailHeight * Constants.aspectRatio16x9
    }

    private var videoDurationLabel: String? {
        guard videoDuration != 0 else { return nil }
        return (videoDuration ?? video?.length)?.formattedAsPlaybackTime()
    }

    private var watchStoppedAtLabel: String? {
        guard let watch else { return nil }

        return watch.stoppedAt.formattedAsPlaybackTime(allowZero: true)
    }

    var timeInfo: Bool {
        videoDurationLabel != nil && (video == nil || !video!.localStreamIsDirectory)
    }

    private var timeLabel: String? {
        if let watch, let watchStoppedAtLabel, let videoDurationLabel, !watch.finished {
            return "\(watchStoppedAtLabel) / \(videoDurationLabel)"
        }
        if let videoDurationLabel {
            return videoDurationLabel
        }
        return nil
    }

    @ViewBuilder private var timeView: some View {
        VStack(alignment: .trailing) {
            PlayingIndicatorView(video: video, height: 10)
                .frame(width: 12, alignment: .trailing)
                .padding(.trailing, 3)
                .padding(.bottom, timeLabel == nil ? 3 : -5)

            if let timeLabel {
                Text(timeLabel)
                    .font(.caption2.weight(.semibold).monospacedDigit())
                    .allowsTightening(true)
                    .padding(2)
                    .modifier(ControlBackgroundModifier())
            }
        }
    }

    @ViewBuilder private var channelLabel: some View {
        if let video, !video.displayAuthor.isEmpty {
            Text(video.displayAuthor)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)
        }
    }
}

struct VideoBanner_Previews: PreviewProvider {
    static var previews: some View {
        ScrollView {
            VideoBanner(video: Video.fixture, playbackTime: CMTime(seconds: 400, preferredTimescale: 10000))
            VideoBanner(video: Video.fixtureUpcomingWithoutPublishedOrViews)
            VideoBanner(video: .local(URL(string: "https://apple.com/a/directory/of/video+that+has+very+long+title+that+will+likely.mp4")!))
            VideoBanner(video: .local(URL(string: "file://a/b/c/d/e/f.mkv")!))
            VideoBanner()
        }
        .frame(maxWidth: 1300)
    }
}
