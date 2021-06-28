import Defaults

extension Defaults.Keys {
    static let layout = Key<ListingLayout>("listingLayout", default: .cells)
    static let tabSelection = Key<TabSelection>("tabSelection", default: .subscriptions)
    static let searchQuery = Key<String>("searchQuery", default: "")
    static let openChannel = Key<Channel?>("openChannel")
}
