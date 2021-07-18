import SwiftUI
import URLImage
import URLImageStore

struct VideoListRowView: View {
    @EnvironmentObject<NavigationState> private var navigationState

    @Environment(\.isFocused) private var focused: Bool

    #if os(iOS)
        @Environment(\.verticalSizeClass) private var verticalSizeClass
    #endif

    var video: Video

    var body: some View {
        #if os(tvOS)
            Button(action: { navigationState.playVideo(video) }) {
                horizontalRow(detailsOnThumbnail: false)
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

            if !detailsOnThumbnail, let time = video.playTime {
                Spacer()

                VStack(alignment: .center) {
                    Spacer()
                    HStack(spacing: 8) {
                        Image(systemName: "clock")
                        Text(time)
                            .fontWeight(.bold)
                    }
                    Spacer()
                }
                .foregroundColor(.secondary)
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

    var additionalDetails: some View {
        VStack {
            if !video.published.isEmpty || video.views != 0 {
                HStack(spacing: 8) {
                    if !video.published.isEmpty {
                        Image(systemName: "calendar")
                        Text(video.published)
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
        }
    }

    func thumbnailWithDetails(
        minWidth: Double = 250,
        maxWidth: Double = .infinity,
        minHeight: Double = 140,
        maxHeight: Double = .infinity
    ) -> some View {
        ZStack(alignment: .trailing) {
            thumbnail(.maxres, minWidth: minWidth, maxWidth: maxWidth, minHeight: minHeight, maxHeight: maxHeight)

            VStack(alignment: .trailing) {
                detailOnThinMaterial(video.author)
                    .offset(x: -5, y: 5)

                Spacer()

                if let time = video.playTime {
                    detailOnThinMaterial(time, bold: true)
                        .offset(x: -5, y: -5)
                }
            }
        }
    }

    func detailOnThinMaterial(_ text: String, bold: Bool = false) -> some View {
        Text(text)
            .fontWeight(bold ? .semibold : .regular)
            .padding(8)
            .background(.thinMaterial)
            .mask(RoundedRectangle(cornerRadius: 12))
    }

    func thumbnail(
        _ quality: ThumbnailQuality,
        minWidth: Double = 320,
        maxWidth: Double = .infinity,
        minHeight: Double = 180,
        maxHeight: Double = .infinity
    ) -> some View {
        Group {
            if let url = video.thumbnailURL(quality: quality) {
                URLImage(url) {
                    EmptyView()
                } inProgress: { _ in
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle())
                } failure: { _, retry in
                    VStack {
                        Button("Retry", action: retry)
                    }
                } content: { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(minWidth: minWidth, maxWidth: maxWidth, minHeight: minHeight, maxHeight: maxHeight)
                }
                .mask(RoundedRectangle(cornerRadius: 12))
            } else {
                Image(systemName: "exclamationmark.square")
            }
        }
        .frame(minWidth: minWidth, maxWidth: maxWidth, minHeight: minHeight, maxHeight: maxHeight)
    }

    func videoDetail(_ text: String, color: Color? = .primary, bold: Bool = false) -> some View {
        Text(text)
            .fontWeight(bold ? .bold : .regular)
        #if os(tvOS)
            .foregroundColor(color)
            .lineLimit(1)
            .truncationMode(.middle)
        #elseif os(iOS) || os(macOS)
            .foregroundColor(focused ? .white : color)
        #endif
    }
}
