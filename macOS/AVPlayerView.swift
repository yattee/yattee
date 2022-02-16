import Defaults
import SwiftUI

struct AVPlayerView: NSViewControllerRepresentable {
    @EnvironmentObject<PlayerModel> private var player

    @State private var controller: AVPlayerViewController?

    init(controller: AVPlayerViewController? = nil) {
        self.controller = controller
    }

    func makeNSViewController(context _: Context) -> AVPlayerViewController {
        if self.controller != nil {
            return self.controller!
        }

        let controller = AVPlayerViewController()

        controller.playerModel = player
        player.controller = controller

        return controller
    }

    func updateNSViewController(_: AVPlayerViewController, context _: Context) {}
}
