import Defaults
import SwiftyJSON

final class OtherDataSettingsGroupExporter: SettingsGroupExporter {
    override var globalJSON: JSON {
        [
            "lastAccountID": Defaults[.lastAccountID] ?? "",
            "lastInstanceID": Defaults[.lastInstanceID] ?? "",

            "playerRate": Defaults[.playerRate],

            "trendingCategory": Defaults[.trendingCategory].rawValue,
            "trendingCountry": Defaults[.trendingCountry].rawValue,

            "subscriptionsViewPage": Defaults[.subscriptionsViewPage].rawValue,
            "subscriptionsListingStyle": Defaults[.subscriptionsListingStyle].rawValue,
            "popularListingStyle": Defaults[.popularListingStyle].rawValue,
            "trendingListingStyle": Defaults[.trendingListingStyle].rawValue,
            "playlistListingStyle": Defaults[.playlistListingStyle].rawValue,
            "channelPlaylistListingStyle": Defaults[.channelPlaylistListingStyle].rawValue,
            "searchListingStyle": Defaults[.searchListingStyle].rawValue,

            "hideShorts": Defaults[.hideShorts],
            "hideWatched": Defaults[.hideWatched]
        ]
    }
}
