import Defaults
import SwiftUI

struct AppleAVPlayerView: NSViewControllerRepresentable {
    @EnvironmentObject<PlayerModel> private var player

    @State private var controller: AppleAVPlayerViewController?

    init(controller: AppleAVPlayerViewController? = nil) {
        self.controller = controller
    }

    func makeNSViewController(context _: Context) -> AppleAVPlayerViewController {
        if self.controller != nil {
            return self.controller!
        }

        let controller = AppleAVPlayerViewController()

        controller.playerModel = player
        player.avPlayerBackend.controller = controller

        return controller
    }

    func updateNSViewController(_: AppleAVPlayerViewController, context _: Context) {}
}
