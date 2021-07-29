import Defaults
import Siesta
import SwiftUI

final class SearchState: ObservableObject {
    @Published var query = SearchQuery()
    @Default(.searchQuery) private var queryText

    private var previousResource: Resource?
    private var resource: Resource!

    @Published var store = Store<[Video]>()

    init() {
        let newQuery = query
        newQuery.query = queryText
        query = newQuery

        resource = InvidiousAPI.shared.search(newQuery)
    }

    var isLoading: Bool {
        resource.isLoading
    }

    func changeQuery(_ changeHandler: @escaping (SearchQuery) -> Void = { _ in }) {
        changeHandler(query)

        let newResource = InvidiousAPI.shared.search(query)
        guard newResource != previousResource else {
            return
        }

        previousResource?.removeObservers(ownedBy: store)
        previousResource = newResource

        queryText = query.query

        resource = newResource
        resource.addObserver(store)
        loadResourceIfNeededAndReplaceStore()
    }

    func loadResourceIfNeededAndReplaceStore() {
        let currentResource = resource!

        if let request = resource.loadIfNeeded() {
            request.onSuccess { response in
                if let videos: [Video] = response.typedContent() {
                    self.replace(videos, for: currentResource)
                }
            }
        } else {
            replace(store.collection, for: currentResource)
        }
    }

    func replace(_ videos: [Video], for resource: Resource) {
        if self.resource == resource {
            store = Store<[Video]>(videos)
        }
    }
}
