import SwiftUI

struct Player: UIViewControllerRepresentable {
    @ObservedObject var playbackState: PlaybackState
    var video: Video?

    func makeUIViewController(context _: Context) -> PlayerViewController {
        let controller = PlayerViewController()

        controller.playbackState = playbackState
        controller.video = video

        return controller
    }

    func updateUIViewController(_: PlayerViewController, context _: Context) {}
}
