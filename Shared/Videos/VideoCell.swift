import Defaults
import SDWebImageSwiftUI
import SwiftUI

struct VideoCell: View {
    var video: Video

    @Environment(\.inNavigationView) private var inNavigationView

    #if os(iOS)
        @Environment(\.verticalSizeClass) private var verticalSizeClass
        @Environment(\.horizontalCells) private var horizontalCells
    #endif

    @EnvironmentObject<PlayerModel> private var player
    @EnvironmentObject<ThumbnailsModel> private var thumbnails

    @Default(.channelOnThumbnail) private var channelOnThumbnail
    @Default(.timeOnThumbnail) private var timeOnThumbnail

    var body: some View {
        Group {
            Button(action: {
                player.playNow(video)

                guard !player.playingInPictureInPicture else {
                    return
                }

                if inNavigationView {
                    player.playerNavigationLinkActive = true
                } else {
                    player.presentPlayer()
                }
            }) {
                content
            }
        }
        .buttonStyle(.plain)
        .contentShape(RoundedRectangle(cornerRadius: 12))
        .contextMenu { VideoContextMenuView(video: video, playerNavigationLinkActive: $player.playerNavigationLinkActive) }
    }

    var content: some View {
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
        .background()
        #endif
    }

    #if os(iOS)
        var horizontalRow: some View {
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
                        Text(video.channel.name)
                            .fontWeight(.semibold)
                            .foregroundColor(.secondary)
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

    var verticalRow: some View {
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
                            Text(video.channel.name)
                                .fontWeight(.semibold)
                                .foregroundColor(.secondary)
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
                            Image(systemName: "calendar")
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

                    if let time = video.length.formattedAsPlaybackTime(), !timeOnThumbnail {
                        Spacer()

                        HStack(spacing: 2) {
                            Image(systemName: "clock")
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

    var additionalDetailsAvailable: Bool {
        video.publishedDate != nil || video.views != 0 || (!timeOnThumbnail && !video.length.formattedAsPlaybackTime().isNil)
    }

    var thumbnail: some View {
        ZStack(alignment: .leading) {
            thumbnailImage

            VStack {
                HStack(alignment: .top) {
                    if video.live {
                        DetailBadge(text: "Live", style: .outstanding)
                    } else if video.upcoming {
                        DetailBadge(text: "Upcoming", style: .informational)
                    }

                    Spacer()

                    if channelOnThumbnail {
                        DetailBadge(text: video.author, style: .prominent)
                    }
                }
                .padding(10)

                Spacer()

                HStack(alignment: .top) {
                    Spacer()

                    if timeOnThumbnail, let time = video.length.formattedAsPlaybackTime() {
                        DetailBadge(text: time, style: .prominent)
                    }
                }
                .padding(10)
            }
            .lineLimit(1)
        }
    }

    var thumbnailImage: some View {
        Group {
            if let url = thumbnails.best(video) {
                WebImage(url: url)
                    .resizable()
                    .placeholder {
                        Rectangle().fill(Color("PlaceholderColor"))
                    }
                    .retryOnAppear(false)
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
        .mask(RoundedRectangle(cornerRadius: 12))
        .modifier(AspectRatioModifier())
    }

    func videoDetail(_ text: String, lineLimit: Int = 1) -> some View {
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
                        .aspectRatio(1.777, contentMode: .fill)
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
