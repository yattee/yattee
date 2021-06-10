import SwiftUI
import URLImage
import URLImageStore

struct VideoThumbnailView: View {
    @Environment(\.isFocused) var focused: Bool

    var video: Video

    var body: some View {
        NavigationLink(destination: PlayerView(provider: VideoDetailsProvider(video.id))) {
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

                VStack(alignment: .leading) {
                    Text(video.title)
                        .foregroundColor(.primary)
                        .bold()
                        .lineLimit(1)

                    Text(video.author)
                        .foregroundColor(.secondary)
                        .lineLimit(1)

                }.padding()
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
            author: "Bear"
        )).frame(maxWidth: 350)
    }
}
