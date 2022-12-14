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
                smallThumbnail

                #if !os(tvOS)
                    progressView
                #endif

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
                                                if let url = video.channel.thumbnailURLOrCached, video != .fixture {
                                                    ThumbnailView(url: url)
                                                        .frame(width: Constants.channelThumbnailSize, height: Constants.channelThumbnailSize)
                                                        .clipShape(Circle())
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
        .contentShape(Rectangle())
        #if os(tvOS)
            .buttonStyle(.card)
        #else
            .buttonStyle(.plain)
        #endif
        #if os(tvOS)
        .padding(.trailing, 10)
        #endif
        .opacity(contentOpacity)
        .id(id ?? video?.videoID ?? video?.id)
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
            ZStack(alignment: .bottomLeading) {
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
                   watch?.finished ?? false
                {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(Color(
                            watchedVideoBadgeColor == .colorSchemeBased ? "WatchProgressBarColor" :
                                watchedVideoBadgeColor == .red ? "AppRedColor" : "AppBlueColor"
                        ))
                        .background(Color.white)
                        .clipShape(Circle())
                        .imageScale(.medium)
                        .offset(x: 5, y: -5)
                }
            }

            if timeOnThumbnail {
                timeView
            }
        }
        .frame(width: thumbnailWidth, height: thumbnailHeight)
        #if os(tvOS)
            .mask(RoundedRectangle(cornerRadius: 12))
        #else
            .mask(RoundedRectangle(cornerRadius: 6))
        #endif
    }

    private var contentOpacity: Double {
        guard saveHistory,
              !watch.isNil,
              watchedVideoStyle == .decreasedOpacity || watchedVideoStyle == .both
        else {
            return 1
        }

        return watch!.finished ? 0.5 : 1
    }

    private var thumbnailWidth: Double {
        #if os(tvOS)
            356
        #else
            120
        #endif
    }

    private var thumbnailHeight: Double {
        #if os(tvOS)
            200
        #else
            72
        #endif
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
        } else if let videoDurationLabel {
            return videoDurationLabel
        } else {
            return nil
        }
    }

    @ViewBuilder private var timeView: some View {
        if let timeLabel {
            Text(timeLabel)
                .font(.caption2.weight(.semibold).monospacedDigit())
                .allowsTightening(true)
                .padding(2)
                .modifier(ControlBackgroundModifier())
        }
    }

    private var progressView: some View {
        ProgressView(value: watchValue, total: progressViewTotal)
            .progressViewStyle(.linear)
            .frame(maxWidth: thumbnailWidth)
            .opacity(showProgressView ? 1 : 0)
            .frame(height: 12)
    }

    private var showProgressView: Bool {
        guard playbackTime != nil,
              let video,
              !video.live
        else {
            return false
        }

        return true
    }

    private var watchValue: Double {
        if finished { return progressViewTotal }

        return progressViewValue
    }

    private var progressViewValue: Double {
        guard videoDuration != 0 else { return 1 }
        return [playbackTime?.seconds, videoDuration].compactMap { $0 }.min() ?? 0
    }

    private var progressViewTotal: Double {
        guard videoDuration != 0 else { return 1 }
        return videoDuration ?? video?.length ?? 1
    }

    private var finished: Bool {
        (progressViewValue / progressViewTotal) * 100 > Double(Defaults[.watchedThreshold])
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
        VStack(spacing: 2) {
            VideoBanner(video: Video.fixture, playbackTime: CMTime(seconds: 400, preferredTimescale: 10000))
            VideoBanner(video: Video.fixtureUpcomingWithoutPublishedOrViews)
            VideoBanner(video: .local(URL(string: "https://apple.com/a/directory/of/video+that+has+very+long+title+that+will+likely.mp4")!))
            VideoBanner(video: .local(URL(string: "file://a/b/c/d/e/f.mkv")!))
            VideoBanner()
        }
        .frame(maxWidth: 1300)
    }
}
