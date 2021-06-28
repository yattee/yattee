import Siesta
import SwiftUI

struct SearchView: View {
    @State private var query = ""

    @ObservedObject private var store = Store<[Video]>()

    var body: some View {
        VideosView(videos: store.collection)
            .searchable(text: $query)
            .onChange(of: query) { newQuery in
                queryChanged(query, newQuery)
            }
    }

    func queryChanged(_ old: String, _ new: String) {
        let oldResource = resource(old)
        oldResource.removeObservers(ownedBy: store)

        let resource = resource(new)
        resource.addObserver(store)
        resource.loadIfNeeded()
    }

    func resource(_ query: String) -> Resource {
        InvidiousAPI.shared.search(query)
    }
}
