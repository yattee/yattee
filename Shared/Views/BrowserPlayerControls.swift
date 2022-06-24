import Foundation
import SDWebImageSwiftUI
import SwiftUI

struct BrowserPlayerControls<Content: View, Toolbar: View>: View {
    enum Context {
        case browser, player
    }

    let content: Content
    let toolbar: Toolbar?

    init(
        context _: Context? = nil,
        @ViewBuilder toolbar: @escaping () -> Toolbar? = { nil },
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.content = content()
        self.toolbar = toolbar()
    }

    init(
        context: Context? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) where Toolbar == EmptyView {
        self.init(context: context, toolbar: { EmptyView() }, content: content)
    }

    var body: some View {
        // TODO: remove
        #if DEBUG
            if #available(iOS 15.0, macOS 12.0, *) {
                Self._printChanges()
            }
        #endif

        return ZStack(alignment: .bottomLeading) {
            content

            #if !os(tvOS)
                VStack(spacing: 0) {
                    toolbar
                        .borderTop(height: 0.4, color: Color("ControlsBorderColor"))
                        .modifier(ControlBackgroundModifier())
                    ControlsBar()
                        .edgesIgnoringSafeArea(.bottom)
                }
            #endif
        }
    }
}

struct PlayerControlsView_Previews: PreviewProvider {
    static var previews: some View {
        BrowserPlayerControls(context: .player) {
            BrowserPlayerControls {
                VStack {
                    Spacer()
                    Text("Hello")
                    Spacer()
                }
            }
            .offset(y: -100)
        }
        .injectFixtureEnvironmentObjects()
    }
}
