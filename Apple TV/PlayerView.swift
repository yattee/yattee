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
            pvc?
                .edgesIgnoringSafeArea(.all)
        }
        .onAppear {
            resource.loadIfNeeded()
        }
    }

    var pvc: PlayerViewController? {
        guard store.item != nil else {
            return nil
        }

        return PlayerViewController(video: store.item!)
    }
}
