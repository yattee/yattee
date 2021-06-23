import SwiftUI
import URLImage
import URLImageStore

struct VideoListRow: View {
    @Environment(\.isFocused) private var focused: Bool

    var video: Video

    var body: some View {
        NavigationLink(destination: PlayerView(id: video.id)) {
            HStack(alignment: .top, spacing: 2) {
                Section {
                    if let thumbnail = video.thumbnailURL {
                        // to replace with AsyncImage when it is fixed with lazy views
                        URLImage(thumbnail) { image in
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 320, height: 180)
                        }
                        .mask(RoundedRectangle(cornerRadius: 12))
                    } else {
                        Image(systemName: "exclamationmark.square")
                    }
                }
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

                            if video.views != 0 {
                                Image(systemName: "eye")
                                Text(video.viewsCount)
                            }
                        }
                        .foregroundColor(.secondary)
                        .padding(.top)
                    }
                    .padding()

                    Spacer()

                    HStack(spacing: 8) {
                        if let time = video.playTime {
                            Image(systemName: "clock")

                            Text(time)
                                .fontWeight(.bold)
                        }
                    }
                    .foregroundColor(.secondary)
                }
                .frame(minHeight: 180)
            }
        }
    }
}

// struct VideoThumbnailView_Previews: PreviewProvider {
//    static var previews: some View {
//        VideoThumbnailView(video: Video(
//            id: "A",
//            title: "A very very long text which",
//            thumbnailURL: URL(string: "https://invidious.home.arekf.net/vi/yXohcxCKqvo/maxres.jpg")!,
//            author: "Bear",
//            length: 240,
//            published: "2 days ago",
//            channelID: ""
//        )).frame(maxWidth: 350)
//    }
// }
