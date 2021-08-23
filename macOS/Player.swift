import SwiftUI

struct Player: NSViewControllerRepresentable {
    @EnvironmentObject<PlaybackState> private var playbackState

    var video: Video!

    func makeNSViewController(context _: Context) -> PlayerViewController {
        let controller = PlayerViewController()

        controller.video = video
        controller.playbackState = playbackState

        return controller
    }

    func updateNSViewController(_: PlayerViewController, context _: Context) {}
}
