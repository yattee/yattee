import Defaults
import SwiftUI

struct Player: UIViewControllerRepresentable {
    @EnvironmentObject<InvidiousAPI> private var api
    @EnvironmentObject<PlaybackModel> private var playback

    var video: Video?

    func makeUIViewController(context _: Context) -> PlayerViewController {
        let controller = PlayerViewController()

        controller.video = video
        controller.playback = playback
        controller.api = api

        controller.resolution = Defaults[.quality]

        return controller
    }

    func updateUIViewController(_: PlayerViewController, context _: Context) {}
}
