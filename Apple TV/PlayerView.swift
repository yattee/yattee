import AVKit
import Foundation
import Siesta
import SwiftUI

struct PlayerView: View {
    @ObservedObject private var store = Store<Video>()

    let resource: Resource

    init(id: String) {
        resource = InvidiousAPI.shared.video(id)
        resource.addObserver(store)
    }

    var body: some View {
        VStack {
            #if os(tvOS)
                pvc
                    .edgesIgnoringSafeArea(.all)
            #else
                if let video = store.item {
                    VStack(alignment: .leading) {
                        Text(video.title)

                            .bold()

                        Text("\(video.author)")

                            .foregroundColor(.secondary)
                            .bold()

                        if !video.published.isEmpty || video.views != 0 {
                            HStack(spacing: 8) {
                                #if os(iOS)
                                    Text(video.playTime ?? "?")
                                        .layoutPriority(1)
                                #endif

                                if !video.published.isEmpty {
                                    Image(systemName: "calendar")
                                    Text(video.published)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                }

                                if video.views != 0 {
                                    Image(systemName: "eye")
                                    Text(video.viewsCount)
                                }
                            }

                            .padding(.top)
                        }
                    }
                    #if os(tvOS)
                        .padding()
                    #else
                    #endif
                }
            #endif
        }
        .onAppear {
            resource.loadIfNeeded()
        }
    }

    // swiftlint:disable implicit_return
    #if !os(macOS)
        var pvc: PlayerViewController? {
            guard store.item != nil else {
                return nil
            }

            return PlayerViewController(video: store.item!)
        }
    #endif
    // swiftlint:enable implicit_return
}
