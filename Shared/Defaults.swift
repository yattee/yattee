import Defaults

extension Defaults.Keys {
    #if os(tvOS)
        static let layout = Key<ListingLayout>("listingLayout", default: .cells)
    #endif
    static let searchQuery = Key<String>("searchQuery", default: "")

    static let searchSortOrder = Key<SearchSortOrder>("searchSortOrder", default: .relevance)
    static let searchDate = Key<SearchDate?>("searchDate")
    static let searchDuration = Key<SearchDuration?>("searchDuration")

    static let selectedPlaylistID = Key<String?>("selectedPlaylistID")
    static let showingAddToPlaylist = Key<Bool>("showingAddToPlaylist", default: false)
    static let videoIDToAddToPlaylist = Key<String?>("videoIDToAddToPlaylist")
}
