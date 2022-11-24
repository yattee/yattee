import SwiftUI

#if !os(macOS)
    struct MPVPlayerView: UIViewControllerRepresentable {
        func makeUIViewController(context _: Context) -> some UIViewController {
            PlayerModel.shared.mpvController
        }

        func updateUIViewController(_: UIViewControllerType, context _: Context) {}
    }
#else
    struct MPVPlayerView: NSViewRepresentable {
        @State private var client = MPVClient()
        @State private var layer = VideoLayer()

        func makeNSView(context _: Context) -> some NSView {
            PlayerModel.shared.mpvBackend.client = client

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
