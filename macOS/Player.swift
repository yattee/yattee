import Defaults
import SwiftUI

struct Player: NSViewControllerRepresentable {
    var video: Video!

    @EnvironmentObject<InvidiousAPI> private var api
    @EnvironmentObject<PlaybackModel> private var playback

    func makeNSViewController(context _: Context) -> PlayerViewController {
        let controller = PlayerViewController()

        controller.video = video
        controller.playback = playback
        controller.api = api

        controller.resolution = Defaults[.quality]

        return controller
    }

    func updateNSViewController(_: PlayerViewController, context _: Context) {}
}
