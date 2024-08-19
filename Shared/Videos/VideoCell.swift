import CoreMedia
import Defaults
import SDWebImageSwiftUI
import SwiftUI

struct VideoCell: View {
    var id: String?
    private var video: Video
    private var watch: Watch?

    @Environment(\.horizontalCells) private var horizontalCells
    @Environment(\.inChannelView) private var inChannelView
    @Environment(\.navigationStyle) private var navigationStyle

    #if os(iOS)
        @Environment(\.verticalSizeClass) private var verticalSizeClass
    #endif

    @Default(.channelOnThumbnail) private var channelOnThumbnail
    @Default(.timeOnThumbnail) private var timeOnThumbnail
    @Default(.roundedThumbnails) private var roundedThumbnails
    @Default(.saveHistory) private var saveHistory
    @Default(.showWatchingProgress) private var showWatchingProgress
    @Default(.watchedVideoStyle) private var watchedVideoStyle
    @Default(.watchedVideoBadgeColor) private var watchedVideoBadgeColor
    @Default(.watchedVideoPlayNowBehavior) private var watchedVideoPlayNowBehavior
    @Default(.showChannelAvatarInVideosListing) private var showChannelAvatarInVideosListing

    private var navigation: NavigationModel { .shared }
    private var player: PlayerModel { .shared }

    init(id: String? = nil, video: Video, watch: Watch? = nil) {
        self.id = id
        self.video = video
        self.watch = watch
    }

    var body: some View {
        Button(action: playAction) {
            content
            #if os(tvOS)
            .frame(width: 580, height: channelOnThumbnail ? 470 : 500)
            #endif
        }
        .opacity(contentOpacity)
        #if os(tvOS)
            .buttonStyle(.card)
        #else
            .buttonStyle(.plain)
        #endif
            .contentShape(RoundedRectangle(cornerRadius: thumbnailRoundingCornerRadius))
            .contextMenu {
                VideoContextMenuView(video: video)
            }
            .id(id ?? video.videoID)
    }

    private var thumbnailRoundingCornerRadius: Double {
        #if os(tvOS)
            return Double(12)
        #else
            return Double(roundedThumbnails ? 12 : 0)
        #endif
    }

    private func playAction() {
        DispatchQueue.main.async {
            guard video.videoID != Video.fixtureID else {
                return
            }

            if player.musicMode {
                player.toggleMusicMode()
            }

            if watchingNow {
                if !player.playingInPictureInPicture {
                    player.show()
                }

                if !playNowContinues {
                    player.backend.seek(to: .zero, seekType: .userInteracted)
                }

                player.play()

                return
            }

            var playAt: CMTime?

            if saveHistory,
               playNowContinues,
               !watch.isNil,
               !watch!.finished
            {
                playAt = .secondsInDefaultTimescale(watch!.stoppedAt)
            }

            player.avPlayerBackend.startPictureInPictureOnPlay = player.playingInPictureInPicture

            player.play(video, at: playAt)
        }
    }

    private var playNowContinues: Bool {
        watchedVideoPlayNowBehavior == .continue
    }

    private var finished: Bool {
        watch?.finished ?? false
    }

    private var watchingNow: Bool {
        player.currentVideo == video
    }

    private var content: some View {
        VStack {
            #if os(iOS)
                if verticalSizeClass == .compact, !horizontalCells {
                    horizontalRow
                        .padding(.vertical, 4)
                } else {
                    verticalRow
                }
            #else
                verticalRow
            #endif
        }
        #if os(macOS)
        .background(Color.secondaryBackground)
        #endif
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

    #if os(iOS)
        private var horizontalRow: some View {
            HStack(alignment: .top, spacing: 2) {
                Section {
                    #if os(tvOS)
                        thumbnailImage
                    #else
                        thumbnail
                    #endif
                }
                .frame(maxWidth: 320)

                VStack(alignment: .leading, spacing: 0) {
                    videoDetail(video.displayTitle, lineLimit: 5)
                        .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)

                    HStack(spacing: Constants.channelDetailsStackSpacing) {
                        if !inChannelView,
                           showChannelAvatarInVideosListing,
                           video != .fixture
                        {
                            ChannelLinkView(channel: video.channel) {
                                if showChannelAvatarInVideosListing {
                                    ChannelAvatarView(channel: video.channel)
                                        .frame(width: Constants.channelThumbnailSize, height: Constants.channelThumbnailSize)
                                } else {
                                    channelLabel(badge: false)
                                }
                            }
                        }

                        if !channelOnThumbnail,
                           !inChannelView
                        {
                            ChannelLinkView(channel: video.channel) {
                                channelLabel(badge: false)
                            }
                        }
                    }

                    if additionalDetailsAvailable {
                        Spacer()

                        HStack(spacing: 15) {
                            if let date = video.publishedDate {
                                VStack {
                                    Image(systemName: "calendar")
                                        .frame(height: 15)
                                    Text(date)
                                }
                            }

                            if video.views > 0 {
                                VStack {
                                    Image(systemName: "eye")
                                        .frame(height: 15)
                                    Text(video.viewsCount!)
                                }
                            }

                            if !timeOnThumbnail, let time = videoDuration {
                                VStack {
                                    Image(systemName: "clock")
                                        .frame(height: 15)
                                    Text(time)
                                }
                            }
                        }
                        .foregroundColor(.secondary)
                    }
                }
                .padding()
                .frame(minHeight: 180)

                #if os(tvOS)
                    if let time = videoDuration || video.live || video.upcoming {
                        Spacer()

                        VStack {
                            Spacer()

                            if let time = videoDuration {
                                HStack(spacing: 4) {
                                    Image(systemName: "clock")
                                    Text(time)
                                        .fontWeight(.bold)
                                }
                                .foregroundColor(.secondary)
                            } else if video.live {
                                DetailBadge(text: "Live", style: .outstanding)
                            } else if video.upcoming {
                                DetailBadge(text: "Upcoming", style: .informational)
                            }

                            Spacer()
                        }
                        .lineLimit(1)
                    }
                #endif
            }
        }
    #endif

    private var videoDuration: String? {
        let length = video.length.isZero ? watch?.videoDuration : video.length
        return length?.formattedAsPlaybackTime()
    }

    private var verticalRow: some View {
        VStack(alignment: .leading, spacing: 0) {
            thumbnail

            VStack(alignment: .leading, spacing: 0) {
                Group {
                    VStack(alignment: .leading, spacing: 0) {
                        videoDetail(video.displayTitle, lineLimit: 2)
                        #if os(tvOS)
                            .frame(minHeight: 60, alignment: .top)
                        #elseif os(macOS)
                            .frame(minHeight: 35, alignment: .top)
                        #else
                            .frame(minHeight: 43, alignment: .top)
                        #endif
                        if !channelOnThumbnail, !inChannelView {
                            ChannelLinkView(channel: video.channel) {
                                HStack(spacing: Constants.channelDetailsStackSpacing) {
                                    if video != .fixture, showChannelAvatarInVideosListing {
                                        ChannelAvatarView(channel: video.channel)
                                            .frame(width: Constants.channelThumbnailSize, height: Constants.channelThumbnailSize)
                                    }

                                    channelLabel(badge: false)
                                }
                            }
                        }
                    }
                    .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                }
                #if os(tvOS)
                .frame(minHeight: channelOnThumbnail ? 80 : 120, alignment: .top)
                #elseif os(macOS)
                .frame(minHeight: channelOnThumbnail ? 52 : 75, alignment: .top)
                #else
                .frame(minHeight: channelOnThumbnail ? 50 : 70, alignment: .top)
                #endif
                .padding(.bottom, 4)

                HStack(spacing: 8) {
                    if channelOnThumbnail,
                       !inChannelView,
                       video.channel.thumbnailURLOrCached != nil,
                       video != .fixture
                    {
                        ChannelLinkView(channel: video.channel) {
                            ChannelAvatarView(channel: video.channel)
                                .frame(width: Constants.channelThumbnailSize, height: Constants.channelThumbnailSize)
                        }
                    }

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

                    if let time, !timeOnThumbnail {
                        Spacer()

                        HStack(spacing: 2) {
                            Text(time)
                        }
                    }
                }
                .lineLimit(1)
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, minHeight: 35, alignment: .topLeading)
                #if os(tvOS)
                    .padding(.bottom, 10)
                #endif
            }
            .padding(.top, 4)
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .topLeading)
            #if os(tvOS)
                .padding(.horizontal, horizontalCells ? 10 : 20)
            #endif
        }
    }

    @ViewBuilder private func channelLabel(badge: Bool = true) -> some View {
        if badge {
            DetailBadge(text: video.author, style: .prominent)
                .foregroundColor(.primary)
        } else {
            Text(verbatim: video.channel.name)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)
        }
    }

    private var additionalDetailsAvailable: Bool {
        video.publishedDate != nil || video.views != 0 ||
            (!timeOnThumbnail && !videoDuration.isNil)
    }

    private var thumbnail: some View {
        ZStack(alignment: .leading) {
            ZStack(alignment: .bottomLeading) {
                thumbnailImage

                ProgressView(value: watch?.progress ?? 0, total: 100)
                    .progressViewStyle(LinearProgressViewStyle(tint: Color("AppRedColor")))
                #if os(tvOS)
                    .padding(.horizontal, 16)
                #else
                    .padding(.horizontal, 10)
                #endif
                #if os(macOS)
                .offset(x: 0, y: 4)
                #else
                .offset(x: 0, y: -3)
                #endif
                .opacity(watch?.isShowingProgress ?? false ? 1 : 0)
            }

            VStack {
                HStack(alignment: .top) {
                    if saveHistory,
                       watchedVideoStyle.isShowingBadge
                    {
                        WatchView(watch: watch, videoID: video.videoID, duration: video.length)
                    }

                    if video.live {
                        DetailBadge(text: "Live", style: .outstanding)
                    } else if video.upcoming {
                        DetailBadge(text: "Upcoming", style: .informational)
                    }

                    Spacer()

                    if channelOnThumbnail, !inChannelView {
                        ChannelLinkView(channel: video.channel) {
                            channelLabel()
                        }
                    }
                }
                #if os(tvOS)
                .padding(16)
                #else
                .padding(10)
                #endif

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    PlayingIndicatorView(video: video, height: 20)
                        .frame(width: 15, alignment: .trailing)
                        .padding(.trailing, 3)
                    HStack {
                        Spacer()

                        if timeOnThumbnail,
                           !video.live,
                           let time
                        {
                            DetailBadge(text: time, style: .prominent)
                        }
                    }
                }
                #if os(tvOS)
                .padding(16)
                #else
                .padding(10)
                #endif
            }
            .lineLimit(1)
        }
    }

    private var thumbnailImage: some View {
        Group {
            VideoCellThumbnail(video: video)

            #if os(tvOS)
                .frame(minHeight: 320)
            #endif
        }
        .mask(RoundedRectangle(cornerRadius: thumbnailRoundingCornerRadius))
        .aspectRatio(Constants.aspectRatio16x9, contentMode: .fill)
    }

    private var time: String? {
        guard var videoTime = videoDuration else {
            return nil
        }

        if !saveHistory || !showWatchingProgress || watch?.finished ?? false {
            return videoTime
        }

        if let stoppedAt = watch?.stoppedAt,
           stoppedAt.isFinite,
           let stoppedAtFormatted = stoppedAt.formattedAsPlaybackTime()
        {
            if (watch?.videoDuration ?? 0) > 0 {
                videoTime = watch!.videoDuration.formattedAsPlaybackTime() ?? "?"
            }
            return "\(stoppedAtFormatted) / \(videoTime)"
        }

        return videoTime
    }

    private func videoDetail(_ text: String, lineLimit: Int = 1) -> some View {
        Text(verbatim: text)
            .fontWeight(.bold)
            .lineLimit(lineLimit)
            .truncationMode(.middle)
    }
}

struct VideoCellThumbnail: View {
    let video: Video
    @ObservedObject private var thumbnails = ThumbnailsModel.shared

    var body: some View {
        GeometryReader { geometry in
            let (url, quality) = thumbnails.best(video)
            let aspectRatio = (quality == .default || quality == .high) ? Constants.aspectRatio4x3 : Constants.aspectRatio16x9

            ThumbnailView(url: url)
                .aspectRatio(aspectRatio, contentMode: .fill)
                .frame(width: geometry.size.width, height: geometry.size.height)
                .clipped()
        }
    }
}

struct VideoCell_Preview: PreviewProvider {
    static var previews: some View {
        Group {
            VideoCell(video: Video.fixture)
        }
        #if os(macOS)
        .frame(maxWidth: 300, maxHeight: 250)
        #elseif os(iOS)
        .frame(maxWidth: 600, maxHeight: 200)
        #endif
        .injectFixtureEnvironmentObjects()
    }
}
