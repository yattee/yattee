import Defaults

extension Defaults.Keys {
    static let layout = Key<ListingLayout>("listingLayout", default: .cells)
    static let tabSelection = Key<TabSelection>("tabSelection", default: .subscriptions)
    static let searchQuery = Key<String>("searchQuery", default: "")
    static let openChannel = Key<Channel?>("openChannel")

    static let searchSortOrder = Key<SearchSortOrder>("searchSortOrder", default: .relevance)
    static let searchDate = Key<SearchDate?>("searchDate", default: nil)
    static let searchDuration = Key<SearchDuration?>("searchDuration", default: nil)
    static let openVideoID = Key<String>("videoID", default: "")
    static let showingVideoDetails = Key<Bool>("showingVideoDetails", default: false)

    static let selectedPlaylistID = Key<String?>("selectedPlaylistID")
}
