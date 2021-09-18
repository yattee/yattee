import Defaults
import SwiftUI

struct VideoView: View {
    @EnvironmentObject<NavigationState> private var navigationState

    #if os(iOS)
        @Environment(\.verticalSizeClass) private var verticalSizeClass
    #endif

    @Environment(\.inNavigationView) private var inNavigationView
    @Environment(\.horizontalCells) private var horizontalCells

    var video: Video
    var layout: ListingLayout

    var body: some View {
        Group {
            if inNavigationView {
                NavigationLink(destination: VideoPlayerView(video)) {
                    content
                }
            } else {
                Button(action: { navigationState.playVideo(video) }) {
                    content
                }
            }
        }
        .modifier(ButtonStyleModifier(layout: layout))
        .contentShape(RoundedRectangle(cornerRadius: 12))
        .contextMenu { VideoContextMenuView(video: video) }
    }

    var content: some View {
        VStack {
            if layout == .cells {
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
            } else {
                horizontalRow
            }
        }
        #if os(macOS)
            .background()
        #endif
    }

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

                        if video.views != 0 {
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
                if video.playTime != nil || video.live || video.upcoming {
                    Spacer()

                    VStack(alignment: .center) {
                        Spacer()

                        if let time = video.playTime {
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
                }
            #endif
        }
    }

    var verticalRow: some View {
        VStack(alignment: .leading, spacing: 0) {
            thumbnail

            VStack(alignment: .leading) {
                videoDetail(video.title, lineLimit: additionalDetailsAvailable ? 2 : 3)
                #if os(tvOS)
                    .frame(minHeight: additionalDetailsAvailable ? 80 : 120, alignment: .top)
                #elseif os(macOS)
                    .frame(minHeight: 30, alignment: .top)
                #else
                    .frame(minHeight: 50, alignment: .top)
                #endif
                .padding(.bottom)

                Group {
                    if additionalDetailsAvailable {
                        HStack(spacing: 8) {
                            if let date = video.publishedDate {
                                Image(systemName: "calendar")
                                Text(date)
                            }

                            if video.views != 0 {
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
                .padding(.bottom, 10)
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
            thumbnailImage(quality: .maxresdefault)

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

                    if let time = video.playTime {
                        DetailBadge(text: time, style: .prominent)
                    }
                }
                .padding(10)
            }
        }
    }

    func thumbnailImage(quality: Thumbnail.Quality) -> some View {
        Group {
            if let url = video.thumbnailURL(quality: quality) {
                AsyncImage(url: url) { image in
                    image
                        .resizable()
                } placeholder: {
                    ProgressView()
                }
            } else {
                Image(systemName: "exclamationmark.square")
            }
        }
        .background(.gray)
        .mask(RoundedRectangle(cornerRadius: 12))
        #if os(tvOS)
            .frame(minHeight: layout == .cells ? 320 : 200)
        #endif
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

    struct ButtonStyleModifier: ViewModifier {
        var layout: ListingLayout

        func body(content: Content) -> some View {
            Section {
                #if os(tvOS)
                    if layout == .cells {
                        content.buttonStyle(.plain)
                    } else {
                        content
                    }
                #else
                    content.buttonStyle(.plain)
                #endif
            }
        }
    }
}
