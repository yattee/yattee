import Defaults
import SDWebImageSwiftUI
import SwiftUI

struct VideoCell: View {
    var video: Video
    @State private var lowQualityThumbnail = false

    @Environment(\.inNavigationView) private var inNavigationView

    #if os(iOS)
        @Environment(\.verticalSizeClass) private var verticalSizeClass
        @Environment(\.horizontalCells) private var horizontalCells
    #endif

    @EnvironmentObject<PlayerModel> private var player

    var body: some View {
        Group {
            Button(action: {
                player.playNow(video)

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
                        thumbnailImage(quality: .medium)
                    #else
                        thumbnail
                    #endif
                }
                .frame(maxWidth: 320)

                VStack(alignment: .leading, spacing: 0) {
                    videoDetail(video.title, lineLimit: 5)
                        .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)

                    videoDetail(video.author)

                    if additionalDetailsAvailable {
                        Spacer()

                        HStack {
                            if let date = video.publishedDate {
                                VStack {
                                    Image(systemName: "calendar")
                                    Text(date)
                                }
                            }

                            if video.views > 0 {
                                VStack {
                                    Image(systemName: "eye")
                                    Text(video.viewsCount!)
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
                videoDetail(video.title, lineLimit: additionalDetailsAvailable ? 2 : 3)
                #if os(tvOS)
                    .frame(minHeight: additionalDetailsAvailable ? 80 : 120, alignment: .top)
                #elseif os(macOS)
                    .frame(minHeight: 30, alignment: .top)
                #else
                    .frame(minHeight: 50, alignment: .top)
                #endif
                .padding(.bottom, 4)

                Group {
                    if additionalDetailsAvailable {
                        HStack(spacing: 8) {
                            if let date = video.publishedDate {
                                Image(systemName: "calendar")
                                Text(date)
                            }

                            if video.views > 0 {
                                Image(systemName: "eye")
                                Text(video.viewsCount!)
                            }
                        }
                        .foregroundColor(.secondary)
                    } else {
                        Spacer()
                    }
                }
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
        video.publishedDate != nil || video.views != 0
    }

    var thumbnail: some View {
        ZStack(alignment: .leading) {
            thumbnailImage(quality: lowQualityThumbnail ? .medium : .maxresdefault)

            VStack {
                HStack(alignment: .top) {
                    if video.live {
                        DetailBadge(text: "Live", style: .outstanding)
                    } else if video.upcoming {
                        DetailBadge(text: "Upcoming", style: .informational)
                    }

                    Spacer()

                    DetailBadge(text: video.author, style: .prominent)
                }
                .padding(10)

                Spacer()

                HStack(alignment: .top) {
                    Spacer()

                    if let time = video.length.formattedAsPlaybackTime() {
                        DetailBadge(text: time, style: .prominent)
                    }
                }
                .padding(10)
            }
            .lineLimit(1)
        }
    }

    func thumbnailImage(quality: Thumbnail.Quality) -> some View {
        WebImage(url: video.thumbnailURL(quality: quality))
            .resizable()
            .placeholder {
                Rectangle().fill(Color("PlaceholderColor"))
            }
            .onFailure { _ in
                lowQualityThumbnail = true
            }
            .indicator(.activity)
            .mask(RoundedRectangle(cornerRadius: 12))
            .modifier(AspectRatioModifier())
        #if os(tvOS)
            .frame(minHeight: 320)
        #endif
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
        .frame(maxWidth: 300, maxHeight: 200)
        .injectFixtureEnvironmentObjects()
    }
}
