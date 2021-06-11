import SwiftUI

struct ContentView: View {
    var body: some View {
        NavigationView {
            TabView {
                PopularVideosView()
                    .tabItem { Text("Popular") }
                
                SearchView()
                    .tabItem { Image(systemName: "magnifyingglass") }
            }
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
