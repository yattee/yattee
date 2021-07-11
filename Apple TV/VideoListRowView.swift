import SwiftUI
import URLImage
import URLImageStore

struct VideoListRowView: View {
    @Environment(\.isFocused) private var focused: Bool

    #if os(iOS)
        @Environment(\.verticalSizeClass) private var verticalSizeClass
    #endif

    var video: Video

    var body: some View {
        #if os(tvOS) || os(macOS)
            NavigationLink(destination: PlayerView(id: video.id)) {
                #if os(tvOS)
                    horizontalRow(detailsOnThumbnail: false)
                #else
                    verticalRow
                #endif
            }
        #else
            ZStack {
                if verticalSizeClass == .compact {
                    horizontalRow(padding: 4)
                } else {
                    verticalRow
                }

                NavigationLink(destination: PlayerView(id: video.id)) {
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
                thumbnailWithDetails
                    .padding(padding)
            } else {
                thumbnail
                    .frame(width: 320, height: 180)
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
            thumbnailWithDetails
                .frame(minWidth: 0, maxWidth: 600)
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

    var thumbnailWithDetails: some View {
        ZStack(alignment: .trailing) {
            thumbnail

            VStack(alignment: .trailing) {
                Text(video.author)
                    .padding(8)
                    .background(.thinMaterial)
                    .mask(RoundedRectangle(cornerRadius: 12))
                    .offset(x: -5, y: 5)

                Spacer()

                if let time = video.playTime {
                    Text(time)
                        .fontWeight(.bold)
                        .padding(8)
                        .background(.thinMaterial)
                        .mask(RoundedRectangle(cornerRadius: 12))
                        .offset(x: -5, y: -5)
                }
            }
        }
    }

    var thumbnail: some View {
        Group {
            if let thumbnail = video.thumbnailURL(quality: "maxres") {
                // to replace with AsyncImage when it is fixed with lazy views
                URLImage(thumbnail) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                }
                .mask(RoundedRectangle(cornerRadius: 12))
            } else {
                Image(systemName: "exclamationmark.square")
            }
        }
        .frame(minWidth: 320, maxWidth: .infinity, minHeight: 180, maxHeight: .infinity)
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
