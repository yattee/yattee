import Defaults
import Siesta
import SwiftUI

struct VideoDetailsView: View {
    @Environment(\.dismiss) private var dismiss

    @EnvironmentObject<NavigationState> private var navigationState

    @ObservedObject private var store = Store<Video>()

    @State private var playVideoLinkActive = false

    var resource: Resource {
        InvidiousAPI.shared.video(video.id)
    }

    var video: Video

    init(_ video: Video) {
        self.video = video
        resource.addObserver(store)
    }

    var body: some View {
        NavigationView {
            HStack {
                Spacer()

                VStack {
                    Spacer()

                    ScrollView(.vertical, showsIndicators: false) {
                        if let video = store.item {
                            VStack(alignment: .center) {
                                ZStack(alignment: .bottom) {
                                    Group {
                                        if let url = video.thumbnailURL(quality: .maxres) {
                                            AsyncImage(url: url) { image in
                                                image
                                                    .resizable()
                                                    .aspectRatio(contentMode: .fill)
                                                    .frame(width: 1600, height: 800)
                                            } placeholder: {
                                                ProgressView()
                                            }
                                        }
                                    }
                                    .frame(width: 1600, height: 800)

                                    VStack(alignment: .leading) {
                                        Text(video.title)
                                            .font(.system(size: 40))

                                        HStack {
                                            playVideoButton

                                            openChannelButton
                                        }
                                    }
                                    .padding(40)
                                    .frame(width: 1600, alignment: .leading)
                                    .background(.thinMaterial)
                                }
                                .mask(RoundedRectangle(cornerRadius: 20))
                                VStack {
                                    Text(video.description)
                                        .lineLimit(nil)
                                        .focusable()
                                }.frame(width: 1600, alignment: .leading)
                            }
                        }
                    }

                    Spacer()
                }

                Spacer()
            }
        }
        .background(.thinMaterial)

        .onAppear {
            resource.loadIfNeeded()
        }

        .edgesIgnoringSafeArea(.all)
    }

    var playVideoButton: some View {
        Button(action: {
            navigationState.returnToDetails = true
            playVideoLinkActive = true
        }) {
            HStack(spacing: 8) {
                Image(systemName: "play.rectangle.fill")
                Text("Play")
            }
        }
        .background(NavigationLink(destination: VideoPlayerView(video), isActive: $playVideoLinkActive) { EmptyView() }.hidden())
    }

    var openChannelButton: some View {
        let channel = video.channel

        return Button("Open \(channel.name) channel") {
            navigationState.openChannel(channel)
            navigationState.tabSelection = .channel(channel.id)
            navigationState.returnToDetails = true
            dismiss()
        }
    }
}
