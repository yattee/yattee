import Defaults
import Repeat
import Siesta
import SwiftUI

final class SearchModel: ObservableObject {
    @Published var store = Store<[ContentItem]>()
    @Published var page: SearchPage?

    @Published var query = SearchQuery()
    @Published var queryText = ""
    @Published var suggestionsText = ""

    @Published var querySuggestions = [String]()
    private var suggestionsDebouncer = Debouncer(.milliseconds(200))

    var accounts = AccountsModel()
    private var resource: Resource!

    var isLoading: Bool {
        resource?.isLoading ?? false
    }

    func changeQuery(_ changeHandler: @escaping (SearchQuery) -> Void = { _ in }) {
        changeHandler(query)

        let newResource = accounts.api.search(query, page: nil)
        guard newResource != resource else {
            return
        }

        page = nil

        resource = newResource
        resource.addObserver(store)

        if !query.isEmpty {
            loadResource()
        }
    }

    func resetQuery(_ query: SearchQuery = SearchQuery()) {
        self.query = query

        let newResource = accounts.api.search(query, page: nil)
        guard newResource != resource else {
            return
        }

        page = nil
        store.replace([])

        if !query.isEmpty {
            resource = newResource
            resource.addObserver(store)
            loadResource()
        }
    }

    func loadResource() {
        let currentResource = resource!

        resource.load().onSuccess { response in
            if let page: SearchPage = response.typedContent() {
                self.page = page
                self.replace(page.results, for: currentResource)
            }
        }
    }

    func replace(_ items: [ContentItem], for resource: Resource) {
        if self.resource == resource {
            store = Store<[ContentItem]>(items)
        }
    }

    var suggestionsResource: Resource? { didSet {
        oldValue?.cancelLoadIfUnobserved()

        objectWillChange.send()
    }}

    func loadSuggestions(_ query: String) {
        suggestionsDebouncer.callback = {
            guard !query.isEmpty else { return }
            DispatchQueue.main.async {
                self.accounts.api.searchSuggestions(query: query).load().onSuccess { response in
                    if let suggestions: [String] = response.typedContent() {
                        self.querySuggestions = suggestions
                    } else {
                        self.querySuggestions = []
                    }
                    self.suggestionsText = query
                }
            }
        }

        suggestionsDebouncer.call()
    }

    func loadNextPage() {
        guard var pageToLoad = page, !pageToLoad.last else {
            return
        }

        if pageToLoad.nextPage.isNil, accounts.app.searchUsesIndexedPages {
            pageToLoad.nextPage = "2"
        }

        resource?.removeObservers(ownedBy: store)

        resource = accounts.api.search(query, page: pageToLoad.nextPage)
        resource.addObserver(store)

        resource
            .load()
            .onSuccess { response in
                if let page: SearchPage = response.typedContent() {
                    var nextPage: Int?
                    if self.accounts.app.searchUsesIndexedPages {
                        nextPage = Int(pageToLoad.nextPage ?? "0")
                    }

                    self.page = page

                    if self.accounts.app.searchUsesIndexedPages {
                        self.page?.nextPage = String((nextPage ?? 1) + 1)
                    }

                    self.replace(self.store.collection + page.results, for: self.resource)
                }
            }
    }
}
