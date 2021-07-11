import SwiftUI
#if os(iOS)
    import Introspect
#endif

struct AppSidebarNavigation: View {
    @EnvironmentObject<NavigationState> private var navigationState

    @State private var didApplyPrimaryViewWorkAround = false

    var body: some View {
        #if os(iOS)
            content.introspectViewController { viewController in
                // workaround for an empty supplementary view on launch
                // the supplementary view is determined by the default selection inside the
                // primary view, but the primary view is not loaded so its selection is not read
                // We work around that by briefly showing the primary view.
                if !didApplyPrimaryViewWorkAround, let splitVC = viewController.children.first as? UISplitViewController {
                    UIView.performWithoutAnimation {
                        splitVC.show(.primary)
                        splitVC.hide(.primary)
                    }
                    didApplyPrimaryViewWorkAround = true
                }
            }
        #else
            content
        #endif
    }

    var content: some View {
        NavigationView {
            sidebar

            Text("Select section")
                .frame(maxWidth: 600)
            Text("Select video")
        }
    }

    var sidebar: some View {
        List {
            NavigationLink(tag: TabSelection.subscriptions, selection: navigationState.tabSelectionOptionalBinding) {
                SubscriptionsView()
            }
            label: {
                Label("Subscriptions", systemImage: "star")
            }

            NavigationLink(tag: TabSelection.popular, selection: navigationState.tabSelectionOptionalBinding) {
                PopularVideosView()
            }
            label: {
                Label("Popular", systemImage: "chart.bar")
            }
        }
    }
}
