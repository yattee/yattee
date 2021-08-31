import Foundation
import SwiftUI

struct VideoDetails: View {
    @EnvironmentObject<Subscriptions> private var subscriptions

    @State private var subscribed = false
    @State private var confirmationShown = false

    var video: Video

    var body: some View {
        VStack(alignment: .leading) {
            Text(video.title)
                .font(.title2.bold())
                .padding(.bottom, 0)

            Divider()

            HStack(alignment: .center) {
                HStack(spacing: 4) {
                    if subscribed {
                        Image(systemName: "star.circle.fill")
                    }
                    VStack(alignment: .leading) {
                        Text(video.channel.name)
                            .font(.system(size: 13))
                            .bold()
                        if let subscribers = video.channel.subscriptionsString {
                            Text("\(subscribers) subscribers")
                                .font(.caption2)
                        }
                    }
                }
                .foregroundColor(.secondary)

                Spacer()

                Section {
                    if subscribed {
                        Button("Unsubscribe") {
                            confirmationShown = true
                        }
                        #if os(iOS)
                            .tint(.gray)
                        #endif
                        .confirmationDialog("Are you you want to unsubscribe from \(video.channel.name)?", isPresented: $confirmationShown) {
                            Button("Unsubscribe") {
                                subscriptions.unsubscribe(video.channel.id)

                                withAnimation {
                                    subscribed.toggle()
                                }
                            }
                        }
                    } else {
                        Button("Subscribe") {
                            subscriptions.subscribe(video.channel.id)

                            withAnimation {
                                subscribed.toggle()
                            }
                        }
                        .tint(.blue)
                    }
                }
                .font(.system(size: 13))
                .buttonStyle(.borderless)
                .buttonBorderShape(.roundedRectangle)
            }
            .padding(.bottom, -1)

            Divider()

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
            .font(.system(size: 12))
            .padding(.bottom, -1)
            .foregroundColor(.secondary)

            Divider()

            HStack {
                Spacer()

                if let views = video.viewsCount {
                    videoDetail(label: "Views", value: views, symbol: "eye.fill")
                }

                if let likes = video.likesCount {
                    Divider()

                    videoDetail(label: "Likes", value: likes, symbol: "hand.thumbsup.circle.fill")
                }

                if let dislikes = video.dislikesCount {
                    Divider()

                    videoDetail(label: "Dislikes", value: dislikes, symbol: "hand.thumbsdown.circle.fill")
                }

                Spacer()
            }
            .frame(maxHeight: 35)
            .foregroundColor(.secondary)

            Divider()

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
        .onAppear {
            subscribed = subscriptions.isSubscribing(video.channel.id)
        }
    }

    func videoDetail(label: String, value: String, symbol: String) -> some View {
        VStack(spacing: 4) {
            HStack(spacing: 2) {
                Image(systemName: symbol)

                Text(label.uppercased())
            }
            .font(.system(size: 9))
            .opacity(0.6)

            Text(value)
        }

        .frame(maxWidth: 100)
    }

    var showScrollIndicators: Bool {
        #if os(macOS)
            false
        #else
            true
        #endif
    }
}

struct VideoDetails_Previews: PreviewProvider {
    static var previews: some View {
        VideoDetails(video: Video.fixture)
            .environmentObject(Subscriptions())
    }
}
