import Defaults
import Repeat
import Siesta
import SwiftUI

final class SearchModel: ObservableObject {
    static var shared = SearchModel()

    @Published var store = Store<[ContentItem]>()
    @Published var page: SearchPage?

    @Published var query = SearchQuery()
    @Published var queryText = ""
    @Published var suggestionsText = ""

    @Published var querySuggestions = [String]()
    private var suggestionsDebouncer = Debouncer(.milliseconds(200))

    @Published var focused = false

    @Default(.showSearchSuggestions) private var showSearchSuggestions

    #if os(iOS)
        var textField: UITextField!
    #elseif os(macOS)
        var textField: NSTextField!
    #endif

    var accounts: AccountsModel { .shared }
    private var resource: Resource!

    init() {
        #if os(iOS)
            addKeyboardDidHideNotificationObserver()
        #endif
    }

    deinit {
        #if os(iOS)
            removeKeyboardDidHideNotificationObserver()
        #endif
    }

    var isLoading: Bool {
        resource?.isLoading ?? false
    }

    func reloadQuery() {
        changeQuery()
    }

    func changeQuery(_ changeHandler: @escaping (SearchQuery) -> Void = { _ in }) {
        changeHandler(query)

        page = nil

        if !query.isEmpty {
            resource = accounts.api.search(query, page: nil)
            resource.addObserver(store)

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
        guard accounts.app.supportsSearchSuggestions, showSearchSuggestions else {
            querySuggestions.removeAll()
            return
        }
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

    #if os(iOS)
        private func addKeyboardDidHideNotificationObserver() {
            NotificationCenter.default.addObserver(self, selector: #selector(onKeyboardDidHide), name: UIResponder.keyboardDidHideNotification, object: nil)
        }

        @objc func onKeyboardDidHide() {
            focused = false
        }

        private func removeKeyboardDidHideNotificationObserver() {
            NotificationCenter.default.removeObserver(self, name: UIResponder.keyboardDidHideNotification, object: nil)
        }
    #endif
}
