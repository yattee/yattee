import SwiftUI

#if !os(macOS)
    struct MPVPlayerView: UIViewControllerRepresentable {
        @EnvironmentObject<PlayerModel> private var player

        @State private var controller = MPVViewController()

        func makeUIViewController(context _: Context) -> some UIViewController {
            player.mpvBackend.controller = controller
            player.mpvBackend.client = controller.client

            return controller
        }

        func updateUIViewController(_: UIViewControllerType, context _: Context) {}
    }
#else
    struct MPVPlayerView: NSViewRepresentable {
        let layer: VideoLayer

        func makeNSView(context _: Context) -> some NSView {
            let vview = VideoView()

            vview.layer = layer
            vview.wantsLayer = true

            return vview
        }

        func updateNSView(_: NSViewType, context _: Context) {}
    }
#endif
