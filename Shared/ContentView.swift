import SwiftUI

struct ContentView: View {
    @StateObject private var state = AppState()

    @State private var tabSelection: TabSelection = .subscriptions

    var body: some View {
        NavigationView {
            TabView(selection: $tabSelection) {
                SubscriptionsView(state: state, tabSelection: $tabSelection)
                    .tabItem { Text("Subscriptions") }
                    .tag(TabSelection.subscriptions)

                PopularVideosView(state: state, tabSelection: $tabSelection)
                    .tabItem { Text("Popular") }
                    .tag(TabSelection.popular)

                if state.showingChannel {
                    ChannelView(state: state, tabSelection: $tabSelection)
                        .tabItem { Text("\(state.channel) Channel") }
                        .tag(TabSelection.channel)
                }

                SearchView(state: state, tabSelection: $tabSelection)
                    .tabItem { Image(systemName: "magnifyingglass") }
                    .tag(TabSelection.search)
            }
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
