import Foundation
import SwiftUI

struct VideoBanner: View {
    let video: Video

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            smallThumbnail

            VStack(alignment: .leading, spacing: 4) {
                Text(video.title)
                    .truncationMode(.middle)
                    .lineLimit(2)
                    .font(.headline)
                    .frame(alignment: .leading)

                HStack {
                    Text(video.author)
                        .lineLimit(1)

                    Spacer()

                    if let time = video.playTime {
                        Text(time)
                            .fontWeight(.light)
                    }
                }
                .foregroundColor(.secondary)
            }
        }
        .contentShape(Rectangle())
        .buttonStyle(.plain)
        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: 100, alignment: .center)
    }

    var smallThumbnail: some View {
        Group {
            if let url = video.thumbnailURL(quality: .medium) {
                AsyncImage(url: url) { image in
                    image
                        .resizable()
                } placeholder: {
                    HStack {
                        ProgressView()
                            .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
                    }
                }
            } else {
                Image(systemName: "exclamationmark.square")
            }
        }
        .background(.gray)
        #if os(tvOS)
            .frame(width: 177, height: 100)
            .mask(RoundedRectangle(cornerRadius: 12))
        #else
            .frame(width: 88, height: 50)
            .mask(RoundedRectangle(cornerRadius: 6))
        #endif
    }
}

struct VideoBanner_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 20) {
            VideoBanner(video: Video.fixture)
            VideoBanner(video: Video.fixtureUpcomingWithoutPublishedOrViews)
        }
        .frame(maxWidth: 900)
    }
}
