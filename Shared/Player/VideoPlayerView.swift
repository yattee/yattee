import AVKit
import Siesta
import SwiftUI

struct VideoPlayerView: View {
    @EnvironmentObject<NavigationState> private var navigationState

    @ObservedObject private var store = Store<Video>()

    @Environment(\.dismiss) private var dismiss

    var resource: Resource {
        InvidiousAPI.shared.video(video.id)
    }

    var video: Video

    init(_ video: Video) {
        self.video = video
        resource.addObserver(store)
    }

    var body: some View {
        VStack {
            Player(video: video)
                .frame(alignment: .leading)

            #if !os(tvOS)
                ScrollView(.vertical) {
                    VStack(alignment: .leading) {
                        Text(video.title)
                        Text(video.author)

                        Button("Done") {
                            dismiss()
                        }
                        .keyboardShortcut(.cancelAction)
                    }
                    .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                }
            #endif
        }
        .onAppear {
            resource.loadIfNeeded()
        }
        .onDisappear {
            resource.removeObservers(ownedBy: store)
            resource.invalidate()

            navigationState.showingVideoDetails = navigationState.returnToDetails
        }
        #if os(macOS)
            .navigationTitle(video.title)
        #elseif os(iOS)
            .navigationBarTitle(video.title, displayMode: .inline)
        #endif
    }
}
