// source: https://stackoverflow.com/a/65002837

import SwiftUI

// we need this workaround only for macOS
// this is the NSView that implements proper `wantsForwardedScrollEvents` method
final class VerticalScrollingFixHostingView<Content>: NSHostingView<Content> where Content: View {
    override func wantsForwardedScrollEvents(for axis: NSEvent.GestureAxis) -> Bool {
        axis == .vertical
    }
}

// this is the SwiftUI wrapper for our NSView
struct VerticalScrollingFixViewRepresentable<Content>: NSViewRepresentable where Content: View {
    let content: Content

    func makeNSView(context _: Context) -> NSHostingView<Content> {
        VerticalScrollingFixHostingView<Content>(rootView: content)
    }

    func updateNSView(_: NSHostingView<Content>, context _: Context) {}
}

// this is the SwiftUI wrapper that makes it easy to insert the view
// into the existing SwiftUI view builders structure
struct VerticalScrollingFixWrapper<Content>: View where Content: View {
    let content: () -> Content

    init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }

    var body: some View {
        VerticalScrollingFixViewRepresentable(content: content())
    }
}

extension View {
    @ViewBuilder func workaroundForVerticalScrollingBug() -> some View {
        VerticalScrollingFixWrapper { self }
    }
}
