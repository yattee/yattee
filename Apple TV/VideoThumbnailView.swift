import SwiftUI
import URLImage
import URLImageStore

struct VideoThumbnailView: View {
    @Environment(\.isFocused) private var focused: Bool

    var video: Video

    var body: some View {
        NavigationLink(destination: PlayerView(id: video.id)) {
            HStack(alignment: .top, spacing: 2) {
                // to replace with AsyncImage when it is fixed with lazy views
                URLImage(video.thumbnailURL) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 320, height: 180)
                }
                .mask(RoundedRectangle(cornerRadius: 12))
                .frame(width: 320, height: 180)

                HStack {
                    VStack(alignment: .leading) {
                        Text(video.title)
                            .foregroundColor(.primary)
                            .bold()
                            .lineLimit(1)

                        Text("\(video.author)")
                            .foregroundColor(.secondary)
                            .bold()
                            .lineLimit(1)

                        HStack(spacing: 8) {
                            Image(systemName: "calendar")
                            Text(video.published)

                            Image(systemName: "eye")
                            Text(video.viewsCount)
                        }
                        .foregroundColor(.secondary)
                        .padding(.top)
                    }
                    .padding()

                    Spacer()

                    HStack(spacing: 8) {
                        Image(systemName: "clock")

                        Text(video.playTime ?? "-")
                            .fontWeight(.bold)
                    }
                    .foregroundColor(.secondary)
                }
                .frame(minHeight: 180)
            }
        }
    }
}

struct VideoThumbnailView_Previews: PreviewProvider {
    static var previews: some View {
        VideoThumbnailView(video: Video(
            id: "A",
            title: "A very very long text which",
            thumbnailURL: URL(string: "https://invidious.home.arekf.net/vi/yXohcxCKqvo/maxres.jpg")!,
            author: "Bear",
            length: 240,
            published: "2 days ago"
        )).frame(maxWidth: 350)
    }
}
