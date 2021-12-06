import Defaults
import Siesta
import SwiftUI

final class SearchModel: ObservableObject {
    @Published var store = Store<[ContentItem]>()

    var accounts = AccountsModel()
    @Published var query = SearchQuery()
    @Published var queryText = ""
    @Published var querySuggestions = Store<[String]>()
    @Published var suggestionsText = ""

    @Published var fieldIsFocused = false

    private var previousResource: Resource?
    private var resource: Resource!

    var isLoading: Bool {
        resource?.isLoading ?? false
    }

    func changeQuery(_ changeHandler: @escaping (SearchQuery) -> Void = { _ in }) {
        changeHandler(query)

        let newResource = accounts.api.search(query)
        guard newResource != previousResource else {
            return
        }

        previousResource?.removeObservers(ownedBy: store)
        previousResource = newResource

        resource = newResource
        resource.addObserver(store)

        if !query.isEmpty {
            loadResourceIfNeededAndReplaceStore()
        }
    }

    func resetQuery(_ query: SearchQuery = SearchQuery()) {
        self.query = query

        let newResource = accounts.api.search(query)
        guard newResource != previousResource else {
            return
        }

        store.replace([])

        previousResource?.removeObservers(ownedBy: store)
        previousResource = newResource

        resource = newResource
        resource.addObserver(store)

        if !query.isEmpty {
            loadResourceIfNeededAndReplaceStore()
        }
    }

    func loadResourceIfNeededAndReplaceStore() {
        let currentResource = resource!

        if let request = resource.loadIfNeeded() {
            request.onSuccess { response in
                if let results: [ContentItem] = response.typedContent() {
                    self.replace(results, for: currentResource)
                }
            }
        } else {
            replace(store.collection, for: currentResource)
        }
    }

    func replace(_ videos: [ContentItem], for resource: Resource) {
        if self.resource == resource {
            store = Store<[ContentItem]>(videos)
        }
    }

    private var suggestionsDebounceTimer: Timer?

    func loadSuggestions(_ query: String) {
        guard !query.isEmpty else {
            return
        }

        suggestionsDebounceTimer?.invalidate()

        suggestionsDebounceTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: false) { _ in
            let resource = self.accounts.api.searchSuggestions(query: query)

            resource.addObserver(self.querySuggestions)
            resource.loadIfNeeded()

            if let request = resource.loadIfNeeded() {
                request.onSuccess { response in
                    if let suggestions: [String] = response.typedContent() {
                        self.querySuggestions = Store<[String]>(suggestions)
                    }
                    self.suggestionsText = query
                }
            } else {
                self.querySuggestions = Store<[String]>(self.querySuggestions.collection)
                self.suggestionsText = query
            }
        }
    }
}
