import SwiftUI

struct SearchView: View {
    @State var query = "" 
    @ObservedObject private var provider = SearchedVideosProvider()
    
    var body: some View {
        VStack {
            SearchedVideosView(provider: provider, query: $query)
                .searchable(text: $query)
        }
    }
}

struct SearchView_Previews: PreviewProvider {
    static var previews: some View {
        SearchView()
    }
}
