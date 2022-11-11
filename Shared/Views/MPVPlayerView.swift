import SwiftUI

#if !os(macOS)
    struct MPVPlayerView: UIViewControllerRepresentable {
        @EnvironmentObject<PlayerModel> private var player

        func makeUIViewController(context _: Context) -> some UIViewController {
            player.mpvController
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

            let view = MPVOGLView()

            if !YatteeApp.isForPreviews {
                client.layer = layer
                layer.client = client

                view.layer = client.layer
                view.wantsLayer = true
            }

            return view
        }

        func updateNSView(_: NSViewType, context _: Context) {}
    }
#endif
