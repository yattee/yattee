import Defaults
import Siesta
import SwiftUI

struct SearchView: View {
    @Default(.searchQuery) var query

    @ObservedObject private var store = Store<[Video]>()

    var body: some View {
        VideosView(videos: store.collection)
            .searchable(text: $query)
            .onAppear {
                queryChanged(new: query)
            }
            .onChange(of: query) { newQuery in
                queryChanged(old: query, new: newQuery)
            }
    }

    func queryChanged(old: String? = nil, new: String) {
        if old != nil {
            let oldResource = resource(old!)
            oldResource.removeObservers(ownedBy: store)
        }

        let resource = resource(new)
        resource.addObserver(store)
        resource.loadIfNeeded()
    }

    func resource(_ query: String) -> Resource {
        InvidiousAPI.shared.search(query)
    }
}
