import Defaults
import SwiftUI

struct VideoView: View {
    @EnvironmentObject<NavigationState> private var navigationState

    @Environment(\.isFocused) private var focused: Bool

    #if os(iOS)
        @Environment(\.verticalSizeClass) private var verticalSizeClass
    #endif

    var layout: ListingLayout?

    var video: Video

    init(video: Video, layout: ListingLayout? = nil) {
        self.video = video
        self.layout = layout

        #if os(tvOS)
            if self.layout == nil {
                self.layout = Defaults[.layout]
            }
        #endif
    }

    var body: some View {
        #if os(tvOS)
            if layout == .cells {
                tvOSButton
                    .buttonStyle(.plain)
                    .padding(.vertical)
            } else {
                tvOSButton
            }
        #elseif os(macOS)
            NavigationLink(destination: VideoPlayerView(video)) {
                verticalRow
            }
        #else
            ZStack {
                #if os(macOS)
                    verticalRow
                #else
                    if verticalSizeClass == .compact {
                        horizontalRow(padding: 4)
                    } else {
                        verticalRow
                    }
                #endif

                NavigationLink(destination: VideoPlayerView(video)) {
                    EmptyView()
                }
                .buttonStyle(PlainButtonStyle())
                .opacity(0)
                .frame(height: 0)
            }
        #endif
    }

    #if os(tvOS)
        var tvOSButton: some View {
            Button(action: { navigationState.playVideo(video) }) {
                if layout == .cells {
                    cellRow
                } else {
                    horizontalRow(detailsOnThumbnail: false)
                }
            }
        }
    #endif

    func horizontalRow(detailsOnThumbnail: Bool = true, padding: Double = 0) -> some View {
        HStack(alignment: .top, spacing: 2) {
            if detailsOnThumbnail {
                thumbnailWithDetails()
                    .padding(padding)
            } else {
                thumbnail(.medium, maxWidth: 320, maxHeight: 180)
            }

            VStack(alignment: .leading, spacing: 0) {
                videoDetail(video.title, bold: true)
                    .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)

                if !detailsOnThumbnail {
                    videoDetail(video.author, color: .secondary, bold: true)
                }

                Spacer()

                additionalDetails
            }
            .padding()
            .frame(minHeight: 180)

            if !detailsOnThumbnail {
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
            }
        }
    }

    var verticalRow: some View {
        VStack(alignment: .leading) {
            thumbnailWithDetails(minWidth: 250, maxWidth: 600, minHeight: 180)
                .frame(idealWidth: 320)
                .padding([.leading, .top, .trailing], 4)

            VStack(alignment: .leading) {
                videoDetail(video.title, bold: true)
                    .padding(.bottom)

                additionalDetails
                    .padding(.bottom, 10)
            }
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 8)
        }
    }

    var cellRow: some View {
        VStack(alignment: .leading) {
            thumbnailWithDetails(minWidth: 550, maxWidth: 550, minHeight: 310, maxHeight: 310)
                .padding([.leading, .top, .trailing], 4)

            VStack(alignment: .leading) {
                videoDetail(video.title, bold: true, lineLimit: additionalDetailsAvailable ? 2 : 3)
                    .frame(minHeight: 80, alignment: .top)
                    .padding(.bottom)

                if additionalDetailsAvailable {
                    additionalDetails
                        .padding(.bottom, 10)
                } else {
                    Spacer()
                }
            }
            .frame(minWidth: 0, maxWidth: .infinity, minHeight: 150, alignment: .leading)
            .padding(10)
        }
        .frame(width: 558)
    }

    var additionalDetailsAvailable: Bool {
        video.publishedDate != nil || video.views != 0
    }

    var additionalDetails: some View {
        HStack(spacing: 8) {
            if let date = video.publishedDate {
                Image(systemName: "calendar")
                Text(date)
            }

            if video.views != 0 {
                Image(systemName: "eye")
                Text(video.viewsCount)
            }
        }
        #if os(tvOS)
            .foregroundColor(.secondary)
        #else
            .foregroundColor(focused ? .white : .secondary)
        #endif
    }

    func thumbnailWithDetails(
        minWidth: Double = 250,
        maxWidth: Double = .infinity,
        minHeight: Double = 140,
        maxHeight: Double = .infinity
    ) -> some View {
        ZStack(alignment: .trailing) {
            thumbnail(.maxres, minWidth: minWidth, maxWidth: maxWidth, minHeight: minHeight, maxHeight: maxHeight)

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

    func thumbnail(
        _ quality: Thumbnail.Quality,
        minWidth: Double = 320,
        maxWidth: Double = .infinity,
        minHeight: Double = 180,
        maxHeight: Double = .infinity
    ) -> some View {
        Group {
            if let url = video.thumbnailURL(quality: quality) {
                AsyncImage(url: url) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(minWidth: minWidth, maxWidth: maxWidth, minHeight: minHeight, maxHeight: maxHeight)
                } placeholder: {
                    ProgressView()
                }
                .mask(RoundedRectangle(cornerRadius: 12))
            } else {
                Image(systemName: "exclamationmark.square")
            }
        }
        .frame(minWidth: minWidth, maxWidth: maxWidth, minHeight: minHeight, maxHeight: maxHeight)
    }

    func videoDetail(_ text: String, color: Color? = .primary, bold: Bool = false, lineLimit: Int = 1) -> some View {
        Text(text)
            .fontWeight(bold ? .bold : .regular)
        #if os(tvOS)
            .foregroundColor(color)
            .lineLimit(lineLimit)
            .truncationMode(.middle)
        #elseif os(iOS) || os(macOS)
            .foregroundColor(focused ? .white : color)
        #endif
    }
}

struct VideoListRowPreview: PreviewProvider {
    static var previews: some View {
        #if os(tvOS)
            List {
                ForEach(Video.allFixtures) { video in
                    VideoView(video: video, layout: .list)
                }
            }
            .listStyle(GroupedListStyle())

            HStack {
                ForEach(Video.allFixtures) { video in
                    VideoView(video: video, layout: .cells)
                }
            }
            .frame(maxHeight: 600)
        #else
            List {
                ForEach(Video.allFixtures) { video in
                    VideoView(video: video, layout: .list)
                }
            }
            #if os(macOS)
                .frame(minHeight: 800)
            #endif

            #if os(iOS)
                List {
                    ForEach(Video.allFixtures) { video in
                        VideoView(video: video, layout: .list)
                    }
                }
                .previewInterfaceOrientation(.landscapeRight)
            #endif
        #endif
    }
}
