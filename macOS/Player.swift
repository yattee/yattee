import SwiftUI

struct Player: NSViewControllerRepresentable {
    @ObservedObject var playbackState: PlaybackState
    var video: Video!

    func makeNSViewController(context _: Context) -> PlayerViewController {
        let controller = PlayerViewController()

        controller.playbackState = playbackState
        controller.video = video

        return controller
    }

    func updateNSViewController(_: PlayerViewController, context _: Context) {}
}
