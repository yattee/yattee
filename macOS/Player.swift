import Defaults
import SwiftUI

struct Player: NSViewControllerRepresentable {
    @EnvironmentObject<PlayerModel> private var player

    var controller: PlayerViewController?

    init(controller: PlayerViewController? = nil) {
        self.controller = controller
    }

    func makeNSViewController(context _: Context) -> PlayerViewController {
        if self.controller != nil {
            return self.controller!
        }

        let controller = PlayerViewController()

        controller.playerModel = player

        return controller
    }

    func updateNSViewController(_: PlayerViewController, context _: Context) {}
}
