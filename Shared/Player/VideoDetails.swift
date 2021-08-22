import Foundation
import SwiftUI

struct VideoDetails: View {
    var video: Video

    var body: some View {
        VStack(alignment: .leading) {
            Text(video.title)
                .font(.title2.bold())

            Text(video.author)
                .foregroundColor(.secondary)

            HStack(spacing: 4) {
                if let published = video.publishedDate {
                    Text(published)
                }

                if let publishedAt = video.publishedAt {
                    if video.publishedDate != nil {
                        Text("•")
                            .foregroundColor(.secondary)
                            .opacity(0.3)
                    }
                    Text(publishedAt.formatted(date: .abbreviated, time: .omitted))
                }
            }
            .padding(.top, 4)
            .font(.system(size: 12))
            .foregroundColor(.secondary)

            HStack {
                if let views = video.viewsCount {
                    VideoDetail(title: "Views", detail: views)
                }

                if let likes = video.likesCount {
                    VideoDetail(title: "Likes", detail: likes, symbol: "hand.thumbsup.circle.fill", symbolColor: Color("VideoDetailLikesSymbolColor"))
                }

                if let dislikes = video.dislikesCount {
                    VideoDetail(title: "Dislikes", detail: dislikes, symbol: "hand.thumbsdown.circle.fill", symbolColor: Color("VideoDetailDislikesSymbolColor"))
                }
            }
            .padding(.horizontal, 1)
            .padding(.vertical, 4)

            #if os(macOS)
                ScrollView(.vertical) {
                    Text(video.description)
                        .font(.caption)
                        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 100, alignment: .leading)
                }
            #else
                Text(video.description)
                    .font(.caption)
            #endif

            ScrollView(.horizontal, showsIndicators: showScrollIndicators) {
                HStack {
                    ForEach(video.keywords, id: \.self) { keyword in
                        HStack(alignment: .center, spacing: 0) {
                            Text("#")
                                .font(.system(size: 11).bold())

                            Text(keyword)
                                .frame(maxWidth: 500)
                        }.foregroundColor(.white)
                            .padding(.vertical, 4)
                            .padding(.horizontal, 8)

                            .background(Color("VideoDetailLikesSymbolColor"))
                            .mask(RoundedRectangle(cornerRadius: 3))

                            .font(.caption)
                    }
                }
                .padding(.bottom, 10)
            }
        }
        .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
        .padding([.horizontal, .bottom])
    }

    var showScrollIndicators: Bool {
        #if os(macOS)
            false
        #else
            true
        #endif
    }
}

struct VideoDetail: View {
    var title: String
    var detail: String
    var symbol = "eye.fill"
    var symbolColor = Color.white

    var body: some View {
        VStack {
            VStack(spacing: 0) {
                HStack(alignment: .center, spacing: 4) {
                    Image(systemName: symbol)
                        .foregroundColor(symbolColor)

                    Text(title.uppercased())

                    Spacer()
                }
                .font(.caption2)
                .padding([.leading, .top], 4)
                .frame(alignment: .leading)

                Divider()
                    .background(.gray)
                    .padding(.vertical, 4)

                Text(detail)
                    .shadow(radius: 1.0)
                    .font(.title3.bold())
            }
        }
        .foregroundColor(.white)
        .background(Color("VideoDetailBackgroundColor"))
        .cornerRadius(6)
        .overlay(RoundedRectangle(cornerRadius: 6)
            .stroke(Color("VideoDetailBorderColor"), lineWidth: 1))
        .frame(maxWidth: 90)
    }
}
