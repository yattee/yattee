import Defaults
import SwiftUI
#if os(iOS)
    import SwiftUIIntrospect
#endif

struct AppSidebarNavigation: View {
    private var navigation: NavigationModel { .shared }

    #if os(iOS)
        @State private var didApplyPrimaryViewWorkAround = false
    #endif

    @Default(.showOpenActionsToolbarItem) private var showOpenActionsToolbarItem

    var body: some View {
        #if os(iOS)
            content.introspect(.viewController, on: .iOS(.v15, .v16, .v17, .v18)) { viewController in
                // workaround for an empty supplementary view on launch
                // the supplementary view is determined by the default selection inside the
                // primary view, but the primary view is not loaded so its selection is not read
                // We work around that by showing the primary view
                if !didApplyPrimaryViewWorkAround, let splitVC = viewController.children.first as? UISplitViewController {
                    UIView.performWithoutAnimation {
                        splitVC.show(.primary)
                    }
                    didApplyPrimaryViewWorkAround = true
                }
            }
        #else
            content
        #endif
    }

    let sidebarMinWidth: Double = 280

    var content: some View {
        NavigationView {
            Sidebar()
                .toolbar { toolbarContent }
                .frame(minWidth: sidebarMinWidth)

            VStack {
                HStack {
                    Spacer()
                    Image(systemName: "4k.tv")
                        .renderingMode(.original)
                        .font(.system(size: 60))
                        .foregroundColor(.accentColor)
                    Spacer()
                }
            }
        }
        .modifier(PlayerOverlayModifier())
        .environment(\.navigationStyle, .sidebar)
    }

    var toolbarContent: some ToolbarContent {
        Group {
            #if os(iOS)
                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    Button(action: { navigation.presentingSettings = true }) {
                        Image(systemName: "gearshape.2")
                    }
                }
            #endif

            ToolbarItemGroup(placement: openVideosToolbarItemPlacement) {
                if showOpenActionsToolbarItem {
                    Button {
                        navigation.presentingOpenVideos = true
                    } label: {
                        Label("Open Videos", systemImage: "play.circle.fill")
                    }
                }
            }

            ToolbarItemGroup(placement: accountsMenuToolbarItemPlacement) {
                AccountViewButton()
            }

            #if os(macOS)
                ToolbarItem(placement: .navigation) {
                    Button {
                        NSApp.keyWindow?.firstResponder?.tryToPerform(#selector(NSSplitViewController.toggleSidebar(_:)), with: nil)
                    } label: {
                        Label("Toggle Sidebar", systemImage: "sidebar.left")
                    }
                }
            #endif
        }
    }

    var openVideosToolbarItemPlacement: ToolbarItemPlacement {
        #if os(iOS)
            return .navigationBarLeading
        #else
            return .automatic
        #endif
    }

    var accountsMenuToolbarItemPlacement: ToolbarItemPlacement {
        #if os(iOS)
            return .bottomBar
        #else
            return .automatic
        #endif
    }
}

struct AppSidebarNavigation_Preview: PreviewProvider {
    static var previews: some View {
        AppSidebarNavigation()
            .injectFixtureEnvironmentObjects()
    }
}
