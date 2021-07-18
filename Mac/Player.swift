import SwiftUI

struct Player: NSViewControllerRepresentable {
    var video: Video!

    func makeNSViewController(context _: Context) -> PlayerViewController {
        let controller = PlayerViewController()
        controller.video = video

        return controller
    }

    func updateNSViewController(_: PlayerViewController, context _: Context) {}
}
