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
        #if os(tvOS)
            NavigationLink(destination: PlayerView(id: video.id)) {
                HStack(alignment: .top, spacing: 2) {
                    roundedThumbnail

                    HStack {
                        VStack(alignment: .leading, spacing: 0) {
                            videoDetail(video.title, bold: true)
                            videoDetail(video.author, color: .secondary, bold: true)

                            Spacer()

                            additionalDetails
                        }
                        .padding()

                        Spacer()
                    }
                    .frame(minHeight: 180)
                }
            }
        #elseif os(macOS)
            NavigationLink(destination: PlayerView(id: video.id)) {
                verticalyAlignedDetails
            }
        #else
            ZStack {
                if verticalSizeClass == .compact {
                    HStack(alignment: .top) {
                        thumbnailWithDetails
                            .frame(minWidth: 0, maxWidth: 320, minHeight: 0, maxHeight: 180)
                            .padding(4)

                        VStack(alignment: .leading) {
                            videoDetail(video.title, bold: true)
                                .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                                .padding(.top, 10)

                            additionalDetails
                                .padding(.top, 4)
                        }
                    }
                } else {
                    verticalyAlignedDetails
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

    var verticalyAlignedDetails: some View {
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

    var thumbnailWithDetails: some View {
        Group {
            ZStack(alignment: .trailing) {
                if let thumbnail = video.thumbnailURL(quality: "maxres") {
                    // to replace with AsyncImage when it is fixed with lazy views
                    URLImage(thumbnail) { image in
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(minWidth: 0, maxWidth: 600, minHeight: 0, maxHeight: .infinity)
                            .background(Color.black)
                    }
                    .mask(RoundedRectangle(cornerRadius: 12))
                } else {
                    Image(systemName: "exclamationmark.square")
                }

                VStack(alignment: .trailing) {
                    Text(video.author)
                        .padding(8)
                        .background(.thinMaterial)
                        .mask(RoundedRectangle(cornerRadius: 12))
                        .offset(x: -5, y: 5)
                        .truncationMode(.middle)

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
    }

    var roundedThumbnail: some View {
        Section {
            if let thumbnail = video.thumbnailURL(quality: "high") {
                // to replace with AsyncImage when it is fixed with lazy views
                URLImage(thumbnail) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(minWidth: 0, maxWidth: 320, minHeight: 0, maxHeight: 180)
                }
                .mask(RoundedRectangle(cornerRadius: 12))
            } else {
                Image(systemName: "exclamationmark.square")
            }
        }
        .frame(width: 320, height: 180)
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
