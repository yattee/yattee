import SwiftUI
#if os(iOS)
    import Introspect
#endif

struct AppSidebarNavigation: View {
    @EnvironmentObject<InvidiousAPI> private var api

    #if os(iOS)
        @EnvironmentObject<NavigationModel> private var navigation
        @State private var didApplyPrimaryViewWorkAround = false
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

            Text("Select section")
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
                            "\(api.account?.url ?? "Not Set")\n" +
                            "Current User: \(api.account?.description ?? "Not set")"
                    )
            }
        }
    }

    var accountsMenuToolbarItemPlacement: ToolbarItemPlacement {
        #if os(iOS)
            return .bottomBar
        #else
            return .automatic
        #endif
    }

    static func symbolSystemImage(_ name: String) -> String {
        let firstLetter = name.first?.lowercased()
        let regex = #"^[a-z0-9]$"#

        let symbolName = firstLetter?.range(of: regex, options: .regularExpression) != nil ? firstLetter! : "questionmark"

        return "\(symbolName).circle"
    }
}
