import SwiftUI

struct Player: UIViewControllerRepresentable {
    @EnvironmentObject<PlaybackState> private var playbackState

    var video: Video?

    func makeUIViewController(context _: Context) -> PlayerViewController {
        let controller = PlayerViewController()

        controller.video = video
        controller.playbackState = playbackState

        return controller
    }

    func updateUIViewController(_: PlayerViewController, context _: Context) {}
}
