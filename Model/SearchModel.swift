import Defaults
import Siesta
import SwiftUI

final class SearchModel: ObservableObject {
    @Published var store = Store<[Video]>()

    @Published var api: InvidiousAPI!
    @Published var query = SearchQuery()
    @Published var queryText = ""
    @Published var querySuggestions = Store<[String]>()

    private var previousResource: Resource?
    private var resource: Resource!

    var isLoading: Bool {
        resource?.isLoading ?? false
    }

    func changeQuery(_ changeHandler: @escaping (SearchQuery) -> Void = { _ in }) {
        changeHandler(query)

        let newResource = api.search(query)
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

        let newResource = api.search(query)
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

    private var suggestionsDebounceTimer: Timer?

    func loadSuggestions(_ query: String) {
        suggestionsDebounceTimer?.invalidate()

        suggestionsDebounceTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: false) { _ in
            let resource = self.api.searchSuggestions(query: query)

            resource.addObserver(self.querySuggestions)
            resource.loadIfNeeded()

            if let request = resource.loadIfNeeded() {
                request.onSuccess { response in
                    if let suggestions: [String] = response.typedContent() {
                        self.querySuggestions = Store<[String]>(suggestions)
                    }
                }
            } else {
                self.querySuggestions = Store<[String]>(self.querySuggestions.collection)
            }
        }
    }
}
