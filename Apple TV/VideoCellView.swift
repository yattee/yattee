import SwiftUI

struct VideoCellView: View {
    @EnvironmentObject<NavigationState> private var navigationState

    var video: Video

    var body: some View {
        Button(action: { navigationState.playVideo(video) }) {
            VStack(alignment: .leading) {
                ZStack {
                    if let url = video.thumbnailURL(quality: .high) {
                        AsyncImage(url: url) { image in
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 550, height: 310)
                        } placeholder: {
                            ProgressView()
                        }
                        .mask(RoundedRectangle(cornerRadius: 12))
                    } else {
                        Image(systemName: "exclamationmark.square")
                            .frame(width: 550, height: 310)
                    }

                    VStack {
                        HStack(alignment: .top) {
                            if video.live {
                                DetailBadge(text: "Live", style: .outstanding)
                            } else if video.upcoming {
                                DetailBadge(text: "Upcoming", style: .informational)
                            }

                            Spacer()

                            DetailBadge(text: video.author, style: .prominent)
                        }
                        .padding(10)

                        Spacer()

                        HStack(alignment: .top) {
                            Spacer()

                            if let time = video.playTime {
                                DetailBadge(text: time, style: .prominent)
                            }
                        }
                        .padding(10)
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

                    HStack(spacing: 8) {
                        if video.publishedDate != nil || video.views != 0 {
                            if let date = video.publishedDate {
                                Image(systemName: "calendar")
                                Text(date)
                            }

                            if video.views != 0 {
                                Image(systemName: "eye")
                                Text(video.viewsCount)
                            }
                        } else {
                            Section {
                                if video.live {
                                    Image(systemName: "camera.fill")
                                    Text("Premiering now")
                                } else {
                                    Image(systemName: "questionmark.app.fill")
                                    Text("date and views unavailable")
                                }
                            }
                            .opacity(0.6)
                        }
                    }
                    .padding([.horizontal, .bottom])
                    .foregroundColor(.secondary)
                }
            }
            .frame(width: 550, alignment: .leading)
        }
        .buttonStyle(.plain)
        .padding(.vertical)
    }
}

struct VideoCellView_Preview: PreviewProvider {
    static var previews: some View {
        HStack {
            VideoCellView(video: Video.fixture)
            VideoCellView(video: Video.fixtureUpcomingWithoutPublishedOrViews)
            VideoCellView(video: Video.fixtureLiveWithoutPublishedOrViews)
        }
    }
}
