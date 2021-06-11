import SwiftUI

struct ContentView: View {
    @StateObject var state = AppState()

    @State var tabSelection: TabSelection = .popular

    var body: some View {
        NavigationView {
            TabView(selection: $tabSelection) {
                PopularVideosView(state: state, tabSelection: $tabSelection)
                    .tabItem { Text("Popular") }
                    .tag(TabSelection.popular)

                if state.showingChannel {
                    ChannelView(state: state, tabSelection: $tabSelection)
                        .tabItem { Text("\(state.channel!) Channel") }
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
