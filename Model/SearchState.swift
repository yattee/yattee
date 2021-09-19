import Defaults
import Siesta
import SwiftUI

final class SearchState: ObservableObject {
    @Published var store = Store<[Video]>()
    @Published var query = SearchQuery()

    @Published var querySuggestions = Store<[String]>()

    private var previousResource: Resource?
    private var resource: Resource!

    init() {
        let newQuery = query
        query = newQuery

        resource = InvidiousAPI.shared.search(newQuery)
    }

    var isLoading: Bool {
        resource.isLoading
    }

    func loadQuerySuggestions(_ query: String) {
        let resource = InvidiousAPI.shared.searchSuggestions(query: query)

        resource.addObserver(querySuggestions)
        resource.loadIfNeeded()

        if let request = resource.loadIfNeeded() {
            request.onSuccess { response in
                if let suggestions: [String] = response.typedContent() {
                    self.querySuggestions = Store<[String]>(suggestions)
                }
            }
        } else {
            querySuggestions = Store<[String]>(querySuggestions.collection)
        }
    }

    func changeQuery(_ changeHandler: @escaping (SearchQuery) -> Void = { _ in }) {
        changeHandler(query)

        let newResource = InvidiousAPI.shared.search(query)
        guard newResource != previousResource else {
            return
        }

        previousResource?.removeObservers(ownedBy: store)
        previousResource = newResource

        resource = newResource
        resource.addObserver(store)
        loadResourceIfNeededAndReplaceStore()
    }

    func resetQuery(_ query: SearchQuery) {
        self.query = query

        let newResource = InvidiousAPI.shared.search(query)
        guard newResource != previousResource else {
            return
        }

        store.replace([])

        previousResource?.removeObservers(ownedBy: store)
        previousResource = newResource

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
