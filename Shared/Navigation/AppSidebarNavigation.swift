import Defaults
import SwiftUI
#if os(iOS)
    import Introspect
#endif

struct AppSidebarNavigation: View {
    @EnvironmentObject<AccountsModel> private var accounts

    #if os(iOS)
        @State private var didApplyPrimaryViewWorkAround = false

        @EnvironmentObject<CommentsModel> private var comments
        @EnvironmentObject<InstancesModel> private var instances
        @EnvironmentObject<NavigationModel> private var navigation
        @EnvironmentObject<PlayerModel> private var player
        @EnvironmentObject<PlayerControlsModel> private var playerControls
        @EnvironmentObject<PlaylistsModel> private var playlists
        @EnvironmentObject<RecentsModel> private var recents
        @EnvironmentObject<SearchModel> private var search
        @EnvironmentObject<SubscriptionsModel> private var subscriptions
        @EnvironmentObject<ThumbnailsModel> private var thumbnailsModel
    #endif

    var body: some View {
        #if os(iOS)
            content.introspectViewController { viewController in
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
                BrowserPlayerControls {
                    HStack(alignment: .center) {
                        Spacer()
                        Image(systemName: "4k.tv")
                            .renderingMode(.original)
                            .font(.system(size: 60))
                            .foregroundColor(.accentColor)
                        Spacer()
                    }
                }
            }
        }
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

            ToolbarItem(placement: accountsMenuToolbarItemPlacement) {
                AccountsMenuView()
                    .help(
                        "Switch Instances and Accounts\n" +
                            "Current Instance: \n" +
                            "\(accounts.current?.url ?? "Not Set")\n" +
                            "Current User: \(accounts.current?.description ?? "Not set")"
                    )
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

    var accountsMenuToolbarItemPlacement: ToolbarItemPlacement {
        #if os(iOS)
            return .bottomBar
        #else
            return .automatic
        #endif
    }
}
