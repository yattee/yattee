import URLImage
import URLImageStore

import SwiftUI

struct VideoCellView: View {
    var video: Video
    var body: some View {
        NavigationLink(destination: PlayerView(id: video.id)) {
            VStack(alignment: .leading) {
                ZStack(alignment: .trailing) {
                    if let thumbnail = video.thumbnailURL {
                        // to replace with AsyncImage when it is fixed with lazy views
                        URLImage(thumbnail) { image in
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 550, height: 310)
                        }
                        .mask(RoundedRectangle(cornerRadius: 12))
                    } else {
                        Image(systemName: "exclamationmark.square")
                            .frame(width: 550, height: 310)
                    }

                    Text(video.author)
                        .padding(8)
                        .background(.thickMaterial)
                        .mask(RoundedRectangle(cornerRadius: 12))
                        .offset(x: -10, y: -120)
                        .truncationMode(.middle)

                    if let time = video.playTime {
                        Text(time)
                            .fontWeight(.bold)
                            .padding(8)
                            .background(.thickMaterial)
                            .mask(RoundedRectangle(cornerRadius: 12))
                            .offset(x: -10, y: 115)
                    }
                }
                .frame(width: 550, height: 310)

                VStack(alignment: .leading) {
                    Text(video.title)
                        .bold()
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .padding(.horizontal)
                        .padding(.bottom, 2)
                        .frame(minHeight: 80, alignment: .top)
                        .truncationMode(.middle)

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
                        .padding([.horizontal, .bottom])
                        .foregroundColor(.secondary)
                    }
                }
            }
            .frame(width: 550, alignment: .leading)
        }
        .buttonStyle(.plain)
        .padding(.vertical)
    }
}
