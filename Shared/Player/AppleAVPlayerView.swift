import AVKit
import Defaults
import SwiftUI

#if os(iOS)
    struct AppleAVPlayerView: UIViewRepresentable {
        func makeUIView(context _: Context) -> some UIView {
            PlayerLayerView(frame: .zero)
        }

        func updateUIView(_: UIViewType, context _: Context) {}
    }
#else
    struct AppleAVPlayerView: UIViewControllerRepresentable {
        func makeUIViewController(context _: Context) -> AppleAVPlayerViewController {
            let controller = AppleAVPlayerViewController()
            PlayerModel.shared.avPlayerBackend.controller = controller

            return controller
        }

        func updateUIViewController(_: AppleAVPlayerViewController, context _: Context) {
            PlayerModel.shared.rebuildTVMenu()
        }
    }
#endif
