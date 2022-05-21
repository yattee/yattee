import CoreMedia
import Defaults
import SDWebImageSwiftUI
import SwiftUI

struct VideoCell: View {
    private var video: Video

    @Environment(\.inNavigationView) private var inNavigationView
    @Environment(\.navigationStyle) private var navigationStyle

    #if os(iOS)
        @Environment(\.verticalSizeClass) private var verticalSizeClass
        @Environment(\.horizontalCells) private var horizontalCells
    #endif

    @EnvironmentObject<AccountsModel> private var accounts
    @EnvironmentObject<NavigationModel> private var navigation
    @EnvironmentObject<PlayerModel> private var player
    @EnvironmentObject<RecentsModel> private var recents
    @EnvironmentObject<ThumbnailsModel> private var thumbnails

    @Default(.channelOnThumbnail) private var channelOnThumbnail
    @Default(.timeOnThumbnail) private var timeOnThumbnail
    @Default(.roundedThumbnails) private var roundedThumbnails
    @Default(.saveHistory) private var saveHistory
    @Default(.showWatchingProgress) private var showWatchingProgress
    @Default(.watchedVideoStyle) private var watchedVideoStyle
    @Default(.watchedVideoBadgeColor) private var watchedVideoBadgeColor
    @Default(.watchedVideoPlayNowBehavior) private var watchedVideoPlayNowBehavior

    @FetchRequest private var watchRequest: FetchedResults<Watch>

    init(video: Video) {
        self.video = video
        _watchRequest = video.watchFetchRequest
    }

    var body: some View {
        Group {
            Button(action: playAction) {
                content
            }
        }
        .opacity(contentOpacity)
        .buttonStyle(.plain)
        .contentShape(RoundedRectangle(cornerRadius: thumbnailRoundingCornerRadius))
        .contextMenu {
            VideoContextMenuView(
                video: video,
                playerNavigationLinkActive: $player.playerNavigationLinkActive
            )
            .environmentObject(accounts)
        }
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

            if watchingNow {
                if !player.playingInPictureInPicture {
                    player.show()
                }

                if !playNowContinues {
                    player.backend.seek(to: .zero)
                }

                player.play()

                return
            }

            var playAt: CMTime?

            if playNowContinues,
               !watch.isNil,
               !watch!.finished
            {
                playAt = .secondsInDefaultTimescale(watch!.stoppedAt)
            }

            player.avPlayerBackend.startPictureInPictureOnPlay = player.playingInPictureInPicture

            player.play(video, at: playAt, inNavigationView: inNavigationView)
        }
    }

    private var playNowContinues: Bool {
        watchedVideoPlayNowBehavior == .continue
    }

    private var watch: Watch? {
        watchRequest.first
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
              watchedVideoStyle == .decreasedOpacity || watchedVideoStyle == .both
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
                    videoDetail(video.title, lineLimit: 5)
                        .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)

                    if !channelOnThumbnail {
                        channelButton(badge: false)
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

                            if !timeOnThumbnail, let time = video.length.formattedAsPlaybackTime() {
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
                    if let time = video.length.formattedAsPlaybackTime() || video.live || video.upcoming {
                        Spacer()

                        VStack(alignment: .center) {
                            Spacer()

                            if let time = video.length.formattedAsPlaybackTime() {
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

    private var verticalRow: some View {
        VStack(alignment: .leading, spacing: 0) {
            thumbnail

            VStack(alignment: .leading, spacing: 0) {
                Group {
                    VStack(alignment: .leading, spacing: 0) {
                        videoDetail(video.title, lineLimit: 2)
                        #if os(tvOS)
                            .frame(minHeight: 60, alignment: .top)
                        #elseif os(macOS)
                            .frame(minHeight: 32, alignment: .top)
                        #else
                            .frame(minHeight: 40, alignment: .top)
                        #endif
                        if !channelOnThumbnail {
                            channelButton(badge: false)
                                .padding(.top, 4)
                                .padding(.bottom, 6)
                        }
                    }
                    .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                }
                #if os(tvOS)
                .frame(minHeight: channelOnThumbnail ? 80 : 120, alignment: .top)
                #elseif os(macOS)
                .frame(minHeight: 35, alignment: .top)
                #else
                .frame(minHeight: 50, alignment: .top)
                #endif
                .padding(.bottom, 4)

                HStack(spacing: 8) {
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

                    if let time = time, !timeOnThumbnail {
                        Spacer()

                        HStack(spacing: 2) {
                            Text(time)
                        }
                    }
                }
                .lineLimit(1)
                .foregroundColor(.secondary)
                .frame(minHeight: 30, alignment: .top)
                #if os(tvOS)
                    .padding(.bottom, 10)
                #endif
            }
            .padding(.top, 4)
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .topLeading)
            #if os(tvOS)
                .padding(.horizontal, 8)
            #endif
        }
    }

    private func channelButton(badge: Bool = true) -> some View {
        Button {
            NavigationModel.openChannel(
                video.channel,
                player: player,
                recents: recents,
                navigation: navigation,
                navigationStyle: navigationStyle
            )
        } label: {
            if badge {
                DetailBadge(text: video.author, style: .prominent)
                    .foregroundColor(.primary)
            } else {
                Text(video.channel.name)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
            }
        }
        .buttonStyle(.plain)
        .help("\(video.channel.name) Channel")
    }

    private var additionalDetailsAvailable: Bool {
        video.publishedDate != nil || video.views != 0 ||
            (!timeOnThumbnail && !video.length.formattedAsPlaybackTime().isNil)
    }

    private var thumbnail: some View {
        ZStack(alignment: .leading) {
            ZStack(alignment: .bottomLeading) {
                thumbnailImage
                if saveHistory, showWatchingProgress, watch?.progress ?? 0 > 0 {
                    ProgressView(value: watch!.progress, total: 100)
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
                }
            }

            VStack {
                HStack(alignment: .top) {
                    if video.live {
                        DetailBadge(text: "Live", style: .outstanding)
                    } else if video.upcoming {
                        DetailBadge(text: "Upcoming", style: .informational)
                    }

                    Spacer()

                    if channelOnThumbnail {
                        channelButton()
                    }
                }
                #if os(tvOS)
                .padding(16)
                #else
                .padding(10)
                #endif

                Spacer()

                HStack(alignment: .center) {
                    if saveHistory,
                       watchedVideoStyle == .badge || watchedVideoStyle == .both,
                       watch?.finished ?? false
                    {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(Color(
                                watchedVideoBadgeColor == .colorSchemeBased ? "WatchProgressBarColor" :
                                    watchedVideoBadgeColor == .red ? "AppRedColor" : "AppBlueColor"
                            ))
                            .background(Color.white)
                            .clipShape(Circle())
                        #if os(tvOS)
                            .font(.system(size: 40))
                        #else
                            .font(.system(size: 30))
                        #endif
                    }
                    Spacer()

                    if timeOnThumbnail,
                       !video.live,
                       let time = time
                    {
                        DetailBadge(text: time, style: .prominent)
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
            if let url = thumbnails.best(video) {
                WebImage(url: url)
                    .resizable()
                    .placeholder {
                        Rectangle().fill(Color("PlaceholderColor"))
                    }
                    .retryOnAppear(true)
                    .onFailure { _ in
                        thumbnails.insertUnloadable(url)
                    }
                    .indicator(.activity)

                #if os(tvOS)
                    .frame(minHeight: 320)
                #endif
            } else {
                ZStack {
                    Color("PlaceholderColor")
                    Image(systemName: "exclamationmark.triangle")
                }
                .font(.system(size: 30))
            }
        }
        .mask(RoundedRectangle(cornerRadius: thumbnailRoundingCornerRadius))
        .modifier(AspectRatioModifier())
    }

    private var time: String? {
        guard var videoTime = video.length.formattedAsPlaybackTime() else {
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
        Text(text)
            .fontWeight(.bold)
            .lineLimit(lineLimit)
            .truncationMode(.middle)
    }

    struct AspectRatioModifier: ViewModifier {
        @Environment(\.horizontalCells) private var horizontalCells

        func body(content: Content) -> some View {
            Group {
                if horizontalCells {
                    content
                } else {
                    content
                        .aspectRatio(
                            VideoPlayerView.defaultAspectRatio,
                            contentMode: .fill
                        )
                }
            }
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
        .frame(maxWidth: 300, maxHeight: 200)
        #endif
        .injectFixtureEnvironmentObjects()
    }
}
