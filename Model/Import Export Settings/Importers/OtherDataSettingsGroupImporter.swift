import Defaults
import SwiftyJSON

struct OtherDataSettingsGroupImporter {
    var json: JSON

    func performImport() {
        if let lastAccountID = json["lastAccountID"].string {
            Defaults[.lastAccountID] = lastAccountID
        }

        if let lastInstanceID = json["lastInstanceID"].string {
            Defaults[.lastInstanceID] = lastInstanceID
        }

        if let playerRate = json["playerRate"].double {
            Defaults[.playerRate] = playerRate
        }

        if let trendingCategoryString = json["trendingCategory"].string,
           let trendingCategory = TrendingCategory(rawValue: trendingCategoryString)
        {
            Defaults[.trendingCategory] = trendingCategory
        }

        if let trendingCountryString = json["trendingCountry"].string,
           let trendingCountry = Country(rawValue: trendingCountryString)
        {
            Defaults[.trendingCountry] = trendingCountry
        }

        if let subscriptionsViewPageString = json["subscriptionsViewPage"].string,
           let subscriptionsViewPage = SubscriptionsView.Page(rawValue: subscriptionsViewPageString)
        {
            Defaults[.subscriptionsViewPage] = subscriptionsViewPage
        }

        if let subscriptionsListingStyle = json["subscriptionsListingStyle"].string {
            Defaults[.subscriptionsListingStyle] = ListingStyle(rawValue: subscriptionsListingStyle) ?? .list
        }

        if let popularListingStyle = json["popularListingStyle"].string {
            Defaults[.popularListingStyle] = ListingStyle(rawValue: popularListingStyle) ?? .list
        }

        if let trendingListingStyle = json["trendingListingStyle"].string {
            Defaults[.trendingListingStyle] = ListingStyle(rawValue: trendingListingStyle) ?? .list
        }

        if let playlistListingStyle = json["playlistListingStyle"].string {
            Defaults[.playlistListingStyle] = ListingStyle(rawValue: playlistListingStyle) ?? .list
        }

        if let channelPlaylistListingStyle = json["channelPlaylistListingStyle"].string {
            Defaults[.channelPlaylistListingStyle] = ListingStyle(rawValue: channelPlaylistListingStyle) ?? .list
        }

        if let searchListingStyle = json["searchListingStyle"].string {
            Defaults[.searchListingStyle] = ListingStyle(rawValue: searchListingStyle) ?? .list
        }

        if let hideShorts = json["hideShorts"].bool {
            Defaults[.hideShorts] = hideShorts
        }

        if let hideWatched = json["hideWatched"].bool {
            Defaults[.hideWatched] = hideWatched
        }
    }
}
