import Defaults
import SwiftUI

struct VideoView: View {
    @EnvironmentObject<NavigationState> private var navigationState

    #if os(iOS)
        @Environment(\.verticalSizeClass) private var verticalSizeClass
    #endif

    var video: Video
    var layout: ListingLayout

    var body: some View {
        Button(action: { navigationState.playVideo(video) }) {
            if layout == .cells {
                #if os(iOS)
                    if verticalSizeClass == .compact {
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
        .buttonStyle(.plain)
    }

    var horizontalRow: some View {
        HStack(alignment: .top, spacing: 2) {
            thumbnailImage(quality: .medium)
                .frame(maxWidth: 320)

            VStack(alignment: .leading, spacing: 0) {
                videoDetail(video.title)
                    .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)

                videoDetail(video.author)

                Spacer()

                additionalDetails
            }
            .padding()
            .frame(minHeight: 180)

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
        .padding(.trailing)
    }

    var verticalRow: some View {
        VStack(alignment: .leading) {
            thumbnail

            VStack(alignment: .leading) {
                videoDetail(video.title, lineLimit: additionalDetailsAvailable ? 2 : 3)
                    .frame(minHeight: 80, alignment: .top)
                #if os(tvOS)
                    .padding(.bottom)
                #endif

                if additionalDetailsAvailable {
                    additionalDetails
                        .padding(.bottom, 10)
                } else {
                    Spacer()
                }
            }
            #if os(tvOS)
                .frame(minWidth: 0, maxWidth: .infinity, minHeight: 150, alignment: .leading)
                .padding(10)
            #endif
        }
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
        .foregroundColor(.secondary)
    }

    var thumbnail: some View {
        ZStack(alignment: .leading) {
            thumbnailImage(quality: .maxres)

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
        .padding([.leading, .top, .trailing], 4)
        .frame(maxWidth: 600)
    }

    func thumbnailImage(quality: Thumbnail.Quality) -> some View {
        Group {
            if let url = video.thumbnailURL(quality: quality) {
                AsyncImage(url: url) { image in
                    image
                        .resizable()
                } placeholder: {
                    ProgressView()
                        .aspectRatio(contentMode: .fill)
                }
                .mask(RoundedRectangle(cornerRadius: 12))
            } else {
                Image(systemName: "exclamationmark.square")
            }
        }
        .frame(minWidth: 320, maxWidth: .infinity, minHeight: 180, maxHeight: .infinity)
        .aspectRatio(1.777, contentMode: .fit)
    }

    func videoDetail(_ text: String, lineLimit: Int = 1) -> some View {
        Text(text)
            .fontWeight(.bold)
            .lineLimit(lineLimit)
            .truncationMode(.middle)
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
