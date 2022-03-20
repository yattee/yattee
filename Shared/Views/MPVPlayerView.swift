import SwiftUI

#if !os(macOS)
    struct MPVPlayerView: UIViewControllerRepresentable {
        @State private var controller = MPVViewController()

        @EnvironmentObject<PlayerModel> private var player

        func makeUIViewController(context _: Context) -> some UIViewController {
            player.mpvBackend.controller = controller
            player.mpvBackend.client = controller.client

            return controller
        }

        func updateUIViewController(_: UIViewControllerType, context _: Context) {}
    }
#else
    struct MPVPlayerView: NSViewRepresentable {
        @State private var client = MPVClient()
        @State private var layer = VideoLayer()

        @EnvironmentObject<PlayerModel> private var player

        func makeNSView(context _: Context) -> some NSView {
            player.mpvBackend.client = client

            client.layer = layer
            layer.client = client

            let view = MPVOGLView()

            view.layer = client.layer
            view.wantsLayer = true

            return view
        }

        func updateNSView(_: NSViewType, context _: Context) {}
    }
#endif
