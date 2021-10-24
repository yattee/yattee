import Defaults
import Foundation

extension Defaults.Keys {
    static let invidiousInstanceID = "default-invidious-instance"
    static let pipedInstanceID = "default-piped-instance"
    static let privateAccountID = "default-private-invidious-account"

    static let instances = Key<[Instance]>("instances", default: [
        .init(app: .piped, id: pipedInstanceID, name: "Public", url: "https://pipedapi.kavin.rocks"),
        .init(app: .invidious, id: invidiousInstanceID, name: "Private", url: "https://invidious.home.arekf.net")
    ])
    static let accounts = Key<[Account]>("accounts", default: [
        .init(
            id: privateAccountID,
            instanceID: invidiousInstanceID,
            name: "arekf",
            url: "https://invidious.home.arekf.net",
            sid: "ki55SJbaQmm0bOxUWctGAQLYPQRgk-CXDPw5Dp4oBmI="
        )
    ])
    static let lastAccountID = Key<Account.ID?>("lastAccountID")
    static let lastInstanceID = Key<Instance.ID?>("lastInstanceID")

    static let sponsorBlockInstance = Key<String>("sponsorBlockInstance", default: "https://sponsor.ajay.app")
    static let sponsorBlockCategories = Key<Set<String>>("sponsorBlockCategories", default: Set(SponsorBlockAPI.categories))

    static let quality = Key<Stream.ResolutionSetting>("quality", default: .hd720pFirstThenBest)

    static let recentlyOpened = Key<[RecentItem]>("recentlyOpened", default: [])

    static let trendingCategory = Key<TrendingCategory>("trendingCategory", default: .default)
    static let trendingCountry = Key<Country>("trendingCountry", default: .us)
}
