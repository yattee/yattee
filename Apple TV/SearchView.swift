import SwiftUI

struct SearchView: View {
    @ObservedObject private var provider = SearchedVideosProvider()

    @State var query = ""

    var body: some View {
        SearchedVideosView(provider: provider, query: $query)
            .searchable(text: $query)
    }
}

struct SearchView_Previews: PreviewProvider {
    static var previews: some View {
        SearchView()
    }
}
