import SwiftUI

struct Player: UIViewControllerRepresentable {
    var video: Video?

    func makeUIViewController(context _: Context) -> PlayerViewController {
        let controller = PlayerViewController()
        controller.video = video

        return controller
    }

    func updateUIViewController(_: PlayerViewController, context _: Context) {}
}
